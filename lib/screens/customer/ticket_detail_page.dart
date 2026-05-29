// ============================================================
// FILE: lib/screens/customer/ticket_detail_page.dart
// UPDATED — filters internal notes, order metadata, bug fixes,
//           uses Brand colors, CachedNetworkImage, TimeUtils,
//           pagination (load more on scroll to top),
//           realtime sender-join fix (A4)
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        RealtimeChannel,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeSubscribeStatus;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/estimate_chat_card.dart';
import '../../widgets/common/chat_message_attachments.dart';
import '../../widgets/common/engineer_route_map.dart';
import '../../l10n/s.dart';

class TicketDetailPage extends StatefulWidget {
  final String ticketId;

  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _activities = [];
  Map<String, dynamic>? _assignedEngineer;
  bool _isLoading = true;
  bool _isSendingMessage = false;
  bool _isHeaderExpanded = true;
  bool _isUploading = false;
  bool _showActivities = false;
  bool _descriptionExpanded = false;
  final List<String> _pendingAttachments = [];

  final List<Map<String, dynamic>> _failedMessages = [];

  String? _currentUserId;
  RealtimeChannel? _chatChannel;
  bool _isOtherOnline = false;

  // ── Pagination ──
  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _scrollController.addListener(_onChatScroll);
    _loadAllData();
    _subscribeToMessages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markMessagesAsRead();
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await Future.wait<dynamic>([
      _loadTicketDetails(),
      _loadMessages(),
      _loadActivities(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadTicketDetails() async {
    try {
      final data =
          await SupabaseConfig.client.from('service_tickets').select('''
        *,
        customer_machines!service_tickets_customer_machine_id_fkey(
          serial_number,
          installation_address,
          machine_catalog!customer_machines_catalog_machine_id_fkey(
            machine_name,
            brand,
            model_number,
            image_url,
            product_images,
            category
          )
        ),
        catalog_machine:machine_catalog!service_tickets_catalog_machine_id_fkey(
          machine_name,
          brand,
          model_number,
          image_url,
          category
        ),
        users!service_tickets_user_id_fkey(
          full_name,
          email,
          company_name,
          phone_number
        ),
        assigned:users!service_tickets_assigned_to_fkey(
          full_name,
          email,
          phone_number,
          profile_photo
        )
      ''').eq('id', widget.ticketId).single();

      if (mounted) {
        setState(() {
          _ticket = data;
          _assignedEngineer = data['assigned'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to load ticket details');
        debugPrint('Error loading ticket: $e');
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final data = await SupabaseConfig.client
          .from('chat_messages')
          .select(
              '*, sender:users!chat_messages_sender_id_fkey(full_name, profile_photo)')
          .eq('ticket_id', widget.ticketId)
          .eq('is_internal', false)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (mounted) {
        final msgList = List<Map<String, dynamic>>.from(data);
        setState(() {
          _messages = msgList.reversed.toList();
          _hasMoreMessages = msgList.length >= _pageSize;
        });
        _scrollToBottom();
        _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint('Error loading messages (trying without filter): $e');
      try {
        final data = await SupabaseConfig.client
            .from('chat_messages')
            .select(
                '*, sender:users!chat_messages_sender_id_fkey(full_name, profile_photo)')
            .eq('ticket_id', widget.ticketId)
            .order('created_at', ascending: false)
            .limit(_pageSize);

        if (mounted) {
          final allMsgs = List<Map<String, dynamic>>.from(data);
          final filtered = allMsgs
              .where((m) => m['is_internal'] != true)
              .toList()
              .reversed
              .toList();
          setState(() {
            _messages = filtered;
            _hasMoreMessages = allMsgs.length >= _pageSize;
          });
          _scrollToBottom();
          _markMessagesAsRead();
        }
      } catch (e2) {
        debugPrint('Error loading messages: $e2');
      }
    }
  }

  Future<void> _loadActivities() async {
    try {
      final data = await SupabaseConfig.client
          .from('ticket_activities')
          .select('*, actor:users!ticket_activities_actor_id_fkey(full_name)')
          .eq('ticket_id', widget.ticketId)
          .order('created_at', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() {
          _activities = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
    }
  }

  Future<void> _markMessagesAsRead() async {
    final now = DateTime.now().toIso8601String();
    try {
      await SupabaseConfig.client
          .from('chat_messages')
          .update({
            'is_read': true,
            'read_at': now,
            'delivered_at': now,
          })
          .eq('ticket_id', widget.ticketId)
          .neq('sender_id', _currentUserId ?? '')
          .eq('is_read', false);
    } catch (_) {}
    // Clear notification badge — once the customer opens the ticket and reads
    // messages, the bell/badge icon should stop showing this ticket as unread.
    // Ticket notifications store the ticket ID in metadata->>'ticket_id' (not
    // in related_id) so we use the JSONB filter to match the right rows.
    if (_currentUserId != null) {
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
  }

  // ═══════════════════════════════════════════════════════════
  //  REALTIME  (A4 — sender-join fix)
  // ═══════════════════════════════════════════════════════════

  void _subscribeToMessages() {
    _chatChannel = SupabaseConfig.client
        .channel('chat_${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          // ── A4 fix: re-fetch with sender join so full_name /
          //            profile_photo / role are always populated ──
          callback: (payload) async {
            try {
              final raw = payload.newRecord;

              // Customer should never see internal notes
              if (raw['is_internal'] == true) return;

              final msgId = raw['id'];
              if (msgId == null) return;

              // Mark as delivered for messages from other senders
              if (raw['sender_id'] != _currentUserId &&
                  raw['delivered_at'] == null) {
                try {
                  await SupabaseConfig.client
                      .from('chat_messages')
                      .update(
                          {'delivered_at': DateTime.now().toIso8601String()})
                      .eq('id', msgId)
                      .filter('delivered_at', 'is', null);
                } catch (e) {
                  debugPrint('delivered_at mark failed: $e');
                }
              }

              // Re-fetch with sender join to get full_name, profile_photo, role
              final enriched =
                  await SupabaseConfig.client.from('chat_messages').select('''
                    *,
                    sender:users!sender_id(
                      id, full_name, profile_photo, role
                    )
                  ''').eq('id', msgId).maybeSingle();

              if (!mounted) return;
              if (enriched == null) return;

              // Skip internal notes (double-check after enrichment)
              if (enriched['is_internal'] == true) return;

              setState(() {
                // Update in-place if ID matches (our own sent message),
                // or add as new if from someone else / not yet in list
                final existingIdx =
                    _messages.indexWhere((m) => m['id'] == enriched['id']);
                if (existingIdx != -1) {
                  // Update to get enriched sender info
                  _messages[existingIdx] =
                      Map<String, dynamic>.from(enriched);
                } else {
                  _messages.add(Map<String, dynamic>.from(enriched));
                }
              });

              if (raw['sender_id'] != _currentUserId) {
                _markMessagesAsRead();
              }

              _scrollToBottomIfNeeded();
            } catch (e) {
              debugPrint('⚠️ Realtime message enrich error: $e');
            }
          },
        )
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
            _loadTicketDetails();
            _loadActivities();
          },
        )
        // ── UPDATE: read-receipt / delivered_at propagation ──
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
              debugPrint('Realtime msg update error: $e');
            }
          },
        )
        // ── PRESENCE: show who is currently viewing this chat ─
        .onPresenceSync((_) {
          if (!mounted) return;
          try {
            final state = _chatChannel!.presenceState();
            final hasOthers =
                state.expand((s) => s.presences).any((p) {
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

  // ─── PAGINATION ────────────────────────────────────────────

  void _onChatScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 50 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty || _isLoadingMore || !_hasMoreMessages) return;

    // Skip optimistic/temp messages
    final serverMessages =
        _messages.where((m) => m['_sending'] != true).toList();
    if (serverMessages.isEmpty) return;

    setState(() => _isLoadingMore = true);

    final oldestCreatedAt = serverMessages.first['created_at'] as String;
    final pixelsBefore = _scrollController.position.pixels;
    final extentBefore = _scrollController.position.maxScrollExtent;

    try {
      final data = await SupabaseConfig.client
          .from('chat_messages')
          .select(
              '*, sender:users!chat_messages_sender_id_fkey(full_name, profile_photo)')
          .eq('ticket_id', widget.ticketId)
          .eq('is_internal', false)
          .lt('created_at', oldestCreatedAt)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (!mounted) return;

      final olderList = List<Map<String, dynamic>>.from(data).reversed.toList();

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
      debugPrint('❌ Load more messages error: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // ─── MESSAGE SENDING ───────────────────────────────────────

  Future<void> _sendMessage({String? text, List<String>? attachments}) async {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty && (attachments == null || attachments.isEmpty)) {
      return;
    }

    setState(() => _isSendingMessage = true);
    if (text == null) _messageController.clear();

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = {
      'id': tempId,
      'ticket_id': widget.ticketId,
      'sender_id': _currentUserId,
      'sender_type': 'customer',
      'message': messageText,
      'attachments': attachments ?? [],
      'is_read': false,
      'is_internal': false,
      'created_at': DateTime.now().toIso8601String(),
      '_sending': true,
    };

    setState(() => _messages.add(tempMessage));
    _scrollToBottom();

    try {
      final insertData = <String, dynamic>{
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'sender_type': 'customer',
        'message': messageText,
        'is_internal': false,
      };
      if (attachments != null && attachments.isNotEmpty) {
        insertData['attachments'] = attachments;
      }

      // Capture real ID so the temp bubble can be updated in-place
      // (avoids the flicker gap between removal and Realtime INSERT event)
      final response = await SupabaseConfig.client
          .from('chat_messages')
          .insert(insertData)
          .select()
          .single();

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            // Update temp message with real DB id and mark as sent
            _messages[idx] = {
              ..._messages[idx],
              'id': response['id'],
              '_sending': false,
              'is_read': false,
              'delivered_at': null,
            };
          }
          _pendingAttachments.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx]['_failed'] = true;
            _messages[idx]['_sending'] = false;
            _failedMessages.add(_messages[idx]);
          }
        });
        _showErrorSnackBar('Message failed to send. Tap to retry.');
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Future<void> _retryMessage(Map<String, dynamic> failedMsg) async {
    setState(() {
      _messages.remove(failedMsg);
      _failedMessages.remove(failedMsg);
    });
    await _sendMessage(
      text: failedMsg['message'],
      attachments: failedMsg['attachments'] != null
          ? List<String>.from(failedMsg['attachments'])
          : null,
    );
  }

  // ─── ATTACHMENTS ───────────────────────────────────────────

  Future<void> _pickAndUploadImage() async {
    try {
      final source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked == null) return;

      setState(() => _isUploading = true);

      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final fileName =
          'ticket_${widget.ticketId}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage
          .from('ticket-attachments')
          .upload(fileName, file);

      final publicUrl = SupabaseConfig.client.storage
          .from('ticket-attachments')
          .getPublicUrl(fileName);

      await _sendMessage(
        text: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : '📎 Image attached',
        attachments: [publicUrl],
      );
      _messageController.clear();
    } catch (e) {
      _showErrorSnackBar('Failed to upload image');
      debugPrint('Upload error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Attach Image',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.3)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSourceButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: Brand.royalBlue,
                    onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildSourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: Brand.lightGreen,
                    onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: isDark ? color.withAlpha(26) : color.withAlpha(15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(38)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          ],
        ),
      ),
    );
  }

  // ─── TICKET ACTIONS ────────────────────────────────────────

  Future<void> _reopenTicket() async {
    final confirmed = await _showConfirmDialog(
      'Reopen Ticket',
      'Are you sure you want to reopen this ticket? This will notify the support team.',
    );
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'status': 'open',
        'reopened_count': (_ticket!['reopened_count'] ?? 0) + 1,
        'closed_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.ticketId);

      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'sender_type': 'system',
        'message': 'Ticket reopened by customer',
        'is_internal': false,
      });

      await _loadAllData();
      if (mounted) _showSuccessSnackBar('Ticket reopened successfully');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to reopen ticket');
      }
    }
  }

  Future<void> _closeTicket() async {
    final confirmed = await _showConfirmDialog(
      'Close Ticket',
      'Are you sure you want to close this ticket?',
    );
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'status': 'closed',
        'closed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.ticketId);

      // Best-effort system message — RLS may forbid sender_type='system'
      // for customer role; do not let that fail the close action.
      try {
        await SupabaseConfig.client.from('chat_messages').insert({
          'ticket_id': widget.ticketId,
          'sender_id': _currentUserId,
          'sender_type': 'system',
          'message': 'Ticket closed by customer',
          'is_internal': false,
        });
      } catch (e) {
        debugPrint('close ticket system message failed (non-fatal): $e');
      }

      await _loadAllData();
      if (mounted) _showSuccessSnackBar('Ticket closed');
    } catch (e) {
      debugPrint('closeTicket failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to close ticket');
      }
    }
  }

  Future<void> _submitRating(int rating, String? feedback) async {
    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'customer_rating': rating,
        'customer_feedback': feedback,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.ticketId);

      await SupabaseConfig.client.from('ticket_activities').insert({
        'ticket_id': widget.ticketId,
        'actor_id': _currentUserId,
        'actor_type': 'customer',
        'activity_type': 'rated',
        'new_value': '$rating',
        'description':
            'Customer rated $rating/5${feedback != null ? ": $feedback" : ""}',
      });

      await _loadTicketDetails();
      if (mounted) _showSuccessSnackBar('Thank you for your feedback!');
    } catch (e) {
      if (mounted) _showErrorSnackBar('Failed to submit rating');
    }
  }

  // ─── UI HELPERS ────────────────────────────────────────────

  Future<bool> _showConfirmDialog(String title, String message) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Brand.royalBlue.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.help_outline_rounded,
                    color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                    size: 30),
              ),
              const SizedBox(height: 18),
              Text(title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.4,
                  )),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontSize: 14,
                      height: 1.4)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: isDark
                                  ? Brand.darkBorderLight
                                  : Brand.borderLight,
                              width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text('Cancel',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Brand.royalBlueDark, Brand.royalBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: Brand.royalBlue.withAlpha(89),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Center(
                          child: Text('Confirm',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: Brand.lightGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── A4: scroll helper used by the enriched realtime callback ──
  void _scrollToBottomIfNeeded() {
    if (!mounted) return;
    final sc = _scrollController;
    if (sc.hasClients) {
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── FORMAT HELPERS ────────────────────────────────────────

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dt.year, dt.month, dt.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatFullDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at ${_formatTime(dt)}';
    } catch (e) {
      return dateStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Brand.royalBlueLight;
      case 'assigned':
        return const Color(0xFF6A1B9A);
      case 'in_progress':
        return Colors.orange;
      case 'waiting_customer':
        return const Color(0xFFFF5722);
      case 'resolved':
        return Brand.lightGreen;
      case 'closed':
        return const Color(0xFF607D8B);
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Icons.radio_button_checked_rounded;
      case 'assigned':
        return Icons.person_add_rounded;
      case 'in_progress':
        return Icons.engineering_rounded;
      case 'waiting_customer':
        return Icons.hourglass_top_rounded;
      case 'resolved':
        return Icons.check_circle_rounded;
      case 'closed':
        return Icons.archive_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFE53935);
      case 'high':
        return const Color(0xFFFF9800);
      case 'medium':
        return Brand.royalBlueLight;
      case 'low':
        return Brand.lightGreen;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Digital Printers':
        return Icons.print_rounded;
      case 'CNC Routers':
        return Icons.precision_manufacturing_rounded;
      case 'Laser Cutters':
        return Icons.content_cut_rounded;
      case 'Finishing Equipment':
        return Icons.construction_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  String _getSenderLabel(Map<String, dynamic> message) {
    final senderData = message['sender'] as Map<String, dynamic>?;
    switch (message['sender_type']) {
      case 'admin':
        return senderData?['full_name'] ?? 'Support Team';
      case 'engineer':
        return senderData?['full_name'] ?? 'Engineer';
      case 'system':
        return 'System';
      default:
        return 'You';
    }
  }

  Color _getSenderColor(String senderType, bool isDark) {
    switch (senderType) {
      case 'admin':
        return isDark ? Brand.royalBlueGlow : Brand.royalBlueDark;
      case 'engineer':
        return Brand.lightGreen;
      case 'system':
        return isDark ? Brand.darkTextSecondary : Brand.subtleLight;
      default:
        return Brand.royalBlueLight;
    }
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    final current = DateTime.parse(_messages[index]['created_at']);
    final previous = DateTime.parse(_messages[index - 1]['created_at']);
    return current.day != previous.day ||
        current.month != previous.month ||
        current.year != previous.year;
  }

  IconData _getActivityIcon(String? type) {
    switch (type) {
      case 'created':
        return Icons.add_circle_rounded;
      case 'status_changed':
        return Icons.swap_horiz_rounded;
      case 'assigned':
        return Icons.person_add_rounded;
      case 'priority_changed':
        return Icons.flag_rounded;
      case 'message_sent':
        return Icons.chat_rounded;
      case 'attachment_added':
        return Icons.attach_file_rounded;
      case 'rated':
        return Icons.star_rounded;
      case 'reopened':
        return Icons.refresh_rounded;
      case 'escalated':
        return Icons.trending_up_rounded;
      case 'quote_sent':
        return Icons.request_quote_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.contains('/image/');
  }

  // ─── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading && _ticket == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.royalBlue.withAlpha(26)
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          strokeWidth: 3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(S.of(context)!.ticketLoading,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    if (_ticket == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      size: 38, color: Colors.red),
                ),
                const SizedBox(height: 18),
                Text(S.of(context)!.ticketLoadFailed,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _loadAllData,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Brand.royalBlueDark, Brand.royalBlue],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Brand.royalBlue.withAlpha(89),
                            blurRadius: 14,
                            offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(S.of(context)!.commonRetry,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final status = _ticket!['status'] ?? 'open';
    // Treat any spec'd closed state (resolved/closed/completed/cancelled) as
    // closed so the chat / actions UI behaves consistently when a job is
    // completed — not just when it's marked resolved/closed.
    final isClosed = const {
      'resolved',
      'closed',
      'completed',
      'cancelled',
    }.contains(status);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Brand.darkCard)
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(isDark),
              _buildTicketHeader(isDark),
              if (_assignedEngineer != null) _buildEngineerBar(isDark),
              if ((_ticket!['status'] as String?) == 'en_route')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.navigation_rounded,
                                size: 16, color: Color(0xFF16A34A)),
                            const SizedBox(width: 6),
                            Text(
                              'Your engineer is on the way',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      EngineerRouteMap(ticketId: widget.ticketId),
                    ],
                  ),
                ),
              if (_ticket!['estimated_resolution'] != null && !isClosed)
                _buildEstimatedResolution(isDark),
              Expanded(child: _buildChatArea(isDark)),
              if (isClosed && _ticket!['customer_rating'] == null)
                _buildRatingPrompt(isDark),
              if (!isClosed)
                _buildMessageInput(isDark)
              else if (_ticket!['customer_rating'] != null)
                _buildClosedBanner(isDark)
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────

  Widget _buildTopBar(bool isDark) {
    final status = _ticket!['status'] ?? 'open';
    final statusColor = _getStatusColor(status);
    final ticketType = _ticket!['ticket_type'] ?? 'support';

    IconData typeIcon;
    String typeLabel;
    switch (ticketType) {
      case 'inquiry':
        typeIcon = Icons.help_outline_rounded;
        typeLabel = 'Inquiry';
        break;
      case 'order':
        typeIcon = Icons.shopping_cart_outlined;
        typeLabel = 'Order';
        break;
      default:
        typeIcon = Icons.build_rounded;
        typeLabel = 'Support';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        border: Border(
            bottom: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                width: 1)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
              ],
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color:
                          isDark ? Brand.darkBorderLight : Brand.borderLight),
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white60 : Brand.royalBlueDark,
                    size: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _ticket!['ticket_number'] ?? 'Ticket',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: statusColor.withAlpha(38)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeIcon, size: 10, color: statusColor),
                          const SizedBox(width: 3),
                          Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_ticket!['escalated'] == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              Colors.orange.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.orange.withAlpha(51)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.priority_high_rounded,
                                size: 10, color: Colors.orange[700]),
                            const SizedBox(width: 2),
                            Text(
                              'ESCALATED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange[700],
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      ' · ${TimeUtils.getTimeAgo(DateTime.parse(_ticket!['created_at']))}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white24
                            : Brand.subtleLight.withAlpha(179),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildBarButton(
            _isHeaderExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            () => setState(() => _isHeaderExpanded = !_isHeaderExpanded),
            isDark,
          ),
          const SizedBox(width: 8),
          _buildBarButton(Icons.more_vert_rounded,
              () => _showTicketOptions(isDark), isDark),
        ],
      ),
    );
  }

  Widget _buildBarButton(IconData icon, VoidCallback onTap, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight),
          ),
          child: Icon(icon,
              color: isDark ? Colors.white60 : Brand.royalBlueDark, size: 20),
        ),
      ),
    );
  }

  // ─── ENGINEER BAR ──────────────────────────────────────────

  Widget _buildEngineerBar(bool isDark) {
    final engineer = _assignedEngineer!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.lightGreen.withAlpha(((isDark ? 0.06 : 0.04) * 255).toInt()),
        border: Border(
          bottom:
              BorderSide(color: Brand.lightGreen.withAlpha(38), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Brand.lightGreen.withAlpha(38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: engineer['profile_photo'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                        imageUrl: engineer['profile_photo'],
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                        placeholder: (_, __) => const Icon(
                            Icons.engineering_rounded,
                            size: 18,
                            color: Brand.lightGreenBright),
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.engineering_rounded,
                            size: 18,
                            color: Brand.lightGreenBright)),
                  )
                : const Icon(Icons.engineering_rounded,
                    size: 18, color: Brand.lightGreenBright),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Assigned to ${engineer['full_name'] ?? 'Engineer'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      ),
                    ),
                    if (_isOtherOnline) ...[
                      const SizedBox(width: 8),
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
                    ],
                  ],
                ),
                if (_ticket!['first_response_at'] != null)
                  Text(
                    'First responded ${TimeUtils.getTimeAgo(DateTime.parse(_ticket!['first_response_at']))}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          if (engineer['phone_number'] != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _launchUrl('tel:${engineer['phone_number']}'),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Brand.lightGreen.withAlpha(38),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.phone_rounded,
                      size: 16, color: Brand.lightGreenBright),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── ESTIMATED RESOLUTION ────────────────────────────────

  Widget _buildEstimatedResolution(bool isDark) {
    final est = DateTime.parse(_ticket!['estimated_resolution']);
    final remaining = est.difference(DateTime.now());
    final isOverdue = remaining.isNegative;
    final color = isOverdue ? Colors.orange : Brand.royalBlueLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(((isDark ? 0.06 : 0.04) * 255).toInt()),
        border: Border(
          bottom: BorderSide(color: color.withAlpha(38)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlpha(31),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isOverdue ? Icons.warning_rounded : Icons.schedule_rounded,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOverdue
                ? 'Resolution overdue by ${remaining.inHours.abs()}h'
                : 'Est. resolution: ${_formatFullDate(_ticket!['estimated_resolution'])}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── TICKET HEADER ─────────────────────────────────────────

  Widget _buildTicketHeader(bool isDark) {
    final customerMachine =
        _ticket!['customer_machines'] as Map<String, dynamic>?;
    final catalog =
        customerMachine?['machine_catalog'] as Map<String, dynamic>?;
    final catalogMachine = _ticket!['catalog_machine'] as Map<String, dynamic>?;
    final displayCatalog = catalog ?? catalogMachine;

    final status = _ticket!['status'] ?? 'open';
    final priority = _ticket!['priority'] ?? 'medium';
    final ticketType = _ticket!['ticket_type'] ?? 'support';

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState: _isHeaderExpanded
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          border: Border(
              bottom: BorderSide(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                  width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                _ticket!['subject'] ?? 'No Subject',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildBadge(
                    icon: _getStatusIcon(status),
                    label: status.replaceAll('_', ' ').toUpperCase(),
                    color: _getStatusColor(status),
                    isDark: isDark,
                  ),
                  _buildBadge(
                    icon: Icons.flag_rounded,
                    label: priority.toUpperCase(),
                    color: _getPriorityColor(priority),
                    isDark: isDark,
                  ),
                  if (_ticket!['category'] != null)
                    _buildBadge(
                      icon: Icons.label_rounded,
                      label: _ticket!['category'],
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      isDark: isDark,
                    ),
                  _buildBadge(
                    icon: Icons.access_time_rounded,
                    label: TimeUtils.getTimeAgo(
                        DateTime.parse(_ticket!['created_at'])),
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    isDark: isDark,
                  ),
                  if (_ticket!['reopened_count'] != null &&
                      _ticket!['reopened_count'] > 0)
                    _buildBadge(
                      icon: Icons.refresh_rounded,
                      label: 'Reopened ${_ticket!['reopened_count']}x',
                      color: Colors.orange,
                      isDark: isDark,
                    ),
                  if (_ticket!['escalated'] == true)
                    _buildBadge(
                      icon: Icons.warning_rounded,
                      label: 'ESCALATED',
                      color: Colors.red,
                      isDark: isDark,
                    ),
                ],
              ),
            ),
            if (ticketType == 'inquiry' || ticketType == 'order') ...[
              const SizedBox(height: 12),
              _buildSalesInfoSection(isDark),
            ],
            if (ticketType == 'order' &&
                _ticket!['metadata'] != null &&
                _ticket!['metadata'] is Map &&
                (_ticket!['metadata'] as Map).isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildOrderMetadataSection(isDark),
            ],
            if (displayCatalog != null) ...[
              const SizedBox(height: 12),
              _buildMachineInfoTile(displayCatalog, customerMachine, isDark),
            ],
            if (_ticket!['description'] != null &&
                _ticket!['description'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDescriptionSection(isDark),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      setState(() => _showActivities = !_showActivities),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timeline_rounded,
                            size: 16,
                            color:
                                isDark ? Brand.royalBlueGlow : Brand.royalBlue),
                        const SizedBox(width: 6),
                        Text(
                          _showActivities
                              ? 'Hide Activity Log'
                              : 'Show Activity Log',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showActivities && _activities.isNotEmpty)
              _buildActivityTimeline(isDark),
            const SizedBox(height: 8),
          ],
        ),
      ),
      secondChild: const SizedBox(width: double.infinity),
    );
  }

  Widget _buildSalesInfoSection(bool isDark) {
    final ticketType = _ticket!['ticket_type'];
    final salesStage = _ticket!['sales_stage'];
    final quantity = _ticket!['quantity'] ?? 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.royalBlue.withAlpha(((isDark ? 0.08 : 0.04) * 255).toInt()),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.royalBlue.withAlpha(31)),
      ),
      child: Column(
        children: [
          if (ticketType == 'order')
            Row(
              children: [
                Icon(Icons.shopping_cart_rounded,
                    size: 16,
                    color: isDark ? Brand.royalBlueGlow : Brand.royalBlue),
                const SizedBox(width: 8),
                Text('Quantity: $quantity',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark)),
              ],
            ),
          if (salesStage != null) ...[
            if (ticketType == 'order') const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    size: 16,
                    color: isDark ? Brand.royalBlueGlow : Brand.royalBlue),
                const SizedBox(width: 8),
                Text(
                  'Stage: ${salesStage.toString().replaceAll('_', ' ').toUpperCase()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
              ],
            ),
          ],
          if (_ticket!['quote_sent_date'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.request_quote_rounded,
                    size: 16, color: Brand.lightGreenBright),
                const SizedBox(width: 8),
                Text(
                  'Quote sent: ${_formatFullDate(_ticket!['quote_sent_date'])}',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
          if (_ticket!['delivery_address'] != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ticket!['delivery_address'],
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderMetadataSection(bool isDark) {
    final meta = _ticket!['metadata'] as Map<String, dynamic>? ?? {};
    final rows = <Widget>[];

    if (meta['machine_name'] != null) {
      rows.add(_buildMetaRow(Icons.precision_manufacturing_rounded, 'Machine',
          meta['machine_name'].toString(), isDark));
    }
    if (meta['quantity'] != null) {
      rows.add(_buildMetaRow(Icons.inventory_2_rounded, 'Quantity',
          meta['quantity'].toString(), isDark));
    }
    if (meta['company_name'] != null) {
      rows.add(_buildMetaRow(Icons.business_rounded, 'Company',
          meta['company_name'].toString(), isDark));
    }
    if (meta['contact_number'] != null) {
      rows.add(_buildMetaRow(Icons.phone_rounded, 'Contact',
          meta['contact_number'].toString(), isDark));
    }
    if (meta['delivery_address'] != null) {
      rows.add(_buildMetaRow(Icons.location_on_rounded, 'Delivery',
          meta['delivery_address'].toString(), isDark));
    }
    if (meta['notes'] != null && meta['notes'].toString().isNotEmpty) {
      rows.add(_buildMetaRow(
          Icons.notes_rounded, 'Notes', meta['notes'].toString(), isDark));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.lightGreen.withAlpha(((isDark ? 0.06 : 0.04) * 255).toInt()),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.lightGreen.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag_rounded,
                  size: 16,
                  color:
                      isDark ? Brand.lightGreenBright : Brand.lightGreenDark),
              const SizedBox(width: 8),
              Text('Order Details',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.lightGreenBright
                          : Brand.lightGreenDark)),
            ],
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineInfoTile(
    Map<String, dynamic> catalog,
    Map<String, dynamic>? customerMachine,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.royalBlueDark.withAlpha(128)
                  : Brand.cardLight,
              borderRadius: BorderRadius.circular(14),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
            ),
            child: _buildMachineImage(catalog, isDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  catalog['machine_name'] ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    catalog['brand'],
                    if (customerMachine?['serial_number'] != null)
                      'S/N: ${customerMachine!['serial_number']}',
                    catalog['model_number'],
                  ].where((e) => e != null).join(' · '),
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineImage(Map<String, dynamic> catalog, bool isDark) {
    String? imageUrl = catalog['image_url'];
    if (imageUrl == null && catalog['product_images'] != null) {
      final images = catalog['product_images'] as List?;
      if (images != null && images.isNotEmpty) {
        imageUrl = images[0].toString();
      }
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          placeholder: (_, __) => Icon(
            _getCategoryIcon(catalog['category']),
            size: 20,
            color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
          ),
          errorWidget: (_, __, ___) => Icon(
            _getCategoryIcon(catalog['category']),
            size: 20,
            color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
          ),
        ),
      );
    }
    return Icon(
      _getCategoryIcon(catalog['category']),
      size: 20,
      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
    );
  }

  Widget _buildDescriptionSection(bool isDark) {
    final description = _ticket!['description'].toString();
    final isLong = description.length > 150;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: _descriptionExpanded ? null : 3,
              overflow: _descriptionExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (isLong)
              GestureDetector(
                onTap: () => setState(
                    () => _descriptionExpanded = !_descriptionExpanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _descriptionExpanded ? 'Show less' : 'Show more',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── ACTIVITY TIMELINE ───────────────────────────────────

  Widget _buildActivityTimeline(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight),
      ),
      child: Column(
        children: _activities.asMap().entries.map((entry) {
          final i = entry.key;
          final activity = entry.value;
          final isLast = i == _activities.length - 1;
          final actorName = activity['actor']?['full_name'] ??
              activity['actor_type'] ??
              'System';

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.royalBlue.withAlpha(31)
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getActivityIcon(activity['activity_type']),
                      size: 14,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 24,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            isDark ? Brand.darkBorderLight : Brand.borderLight,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity['description'] ??
                            activity['activity_type'] ??
                            '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$actorName · ${TimeUtils.getTimeAgo(DateTime.parse(activity['created_at']))}',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CHAT AREA ───────────────────────────────────────────

  Widget _buildChatArea(bool isDark) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.royalBlue.withAlpha(26)
                    : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 34,
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue),
            ),
            const SizedBox(height: 18),
            Text(S.of(context)!.ticketNoMessages,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(S.of(context)!.ticketStartConversation,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    final offset = _isLoadingMore ? 1 : 0;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + offset,
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == 0) {
          return _buildLoadingMoreIndicator(isDark);
        }
        final msgIndex = index - offset;
        final message = _messages[msgIndex];
        final showDateHeader = _shouldShowDateHeader(msgIndex);
        return Column(
          children: [
            if (showDateHeader) _buildDateSeparator(msgIndex, isDark),
            _buildMessageBubble(message, isDark),
          ],
        );
      },
    );
  }

  Widget _buildDateSeparator(int index, bool isDark) {
    final date = DateTime.parse(_messages[index]['created_at']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: Divider(
                  color: isDark ? Brand.darkBorderLight : Brand.borderLight)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight),
              ),
              child: Text(
                _formatDateHeader(date),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ),
          ),
          Expanded(
              child: Divider(
                  color: isDark ? Brand.darkBorderLight : Brand.borderLight)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isDark) {
    final isMyMessage = message['sender_id'] == _currentUserId;
    final isSystem = message['sender_type'] == 'system';
    final timestamp = DateTime.parse(message['created_at']);
    final senderType = message['sender_type'] ?? 'customer';
    final senderColor = _getSenderColor(senderType, isDark);
    final isSending = message['_sending'] == true;
    final isFailed = message['_failed'] == true;
    final attachments = message['attachments'] as List?;
    final msgType = message['message_type'] as String? ?? 'text';
    final metadata =
        message['metadata'] as Map<String, dynamic>? ?? const {};

    // Estimate card (full-width, with approve/reject for the customer)
    if (msgType == 'quote') {
      final qid = metadata['quotation_id'] as String?;
      return EstimateChatCard(
        message: message,
        metadata: metadata,
        isDark: isDark,
        isCustomerView: true,
        onApprove: (qid == null)
            ? null
            : () async {
                try {
                  await EstimateChatActions.approveEstimate(
                    quotationId: qid,
                    ticketId: widget.ticketId,
                    currentUserId: _currentUserId ?? '',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Estimate approved')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
        onReject: (qid == null)
            ? null
            : () async {
                try {
                  await EstimateChatActions.rejectEstimate(
                    quotationId: qid,
                    ticketId: widget.ticketId,
                    currentUserId: _currentUserId ?? '',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Estimate rejected')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
      );
    }

    // System message
    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Brand.royalBlue.withAlpha(15)
              : Brand.royalBlueSurface.withAlpha(128),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.royalBlue.withAlpha(26)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 16,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message['message'] ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              _formatTime(timestamp),
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white12 : Colors.black26,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: isFailed ? () => _retryMessage(message) : null,
        onLongPress: () => _showMessageOptions(message, isDark),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Column(
            crossAxisAlignment:
                isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMyMessage)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(builder: (_) {
                        final senderPhoto = (message['sender']
                                as Map<String, dynamic>?)?['profile_photo']
                            as String?;
                        final box = Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: senderColor.withAlpha(
                                ((isDark ? 0.15 : 0.1) * 255).toInt()),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            senderType == 'admin'
                                ? Icons.support_agent_rounded
                                : Icons.engineering_rounded,
                            size: 15,
                            color: senderColor,
                          ),
                        );
                        if (senderPhoto == null || senderPhoto.isEmpty) {
                          return box;
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: senderPhoto,
                            width: 26,
                            height: 26,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => box,
                            errorWidget: (_, __, ___) => box,
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      Text(
                        _getSenderLabel(message),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: senderColor,
                        ),
                      ),
                    ],
                  ),
                ),

              // Bubble
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isFailed
                      ? Colors.red.withAlpha(((isDark ? 0.1 : 0.06) * 255).toInt())
                      : isMyMessage
                          ? (isDark ? Brand.royalBlueDark : Brand.royalBlueDark)
                          : (isDark ? Brand.darkCard : Brand.cardLight),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMyMessage ? 20 : 4),
                    bottomRight: Radius.circular(isMyMessage ? 4 : 20),
                  ),
                  border: isFailed
                      ? Border.all(color: Colors.red.withAlpha(64))
                      : isMyMessage
                          ? (isDark
                              ? Border.all(
                                  color: Brand.royalBlue.withAlpha(51))
                              : null)
                          : Border.all(
                              color: isDark
                                  ? Brand.darkBorder
                                  : Brand.borderLight),
                  boxShadow: isDark ? null : [
                    BoxShadow(
                      color: isMyMessage
                          ? Brand.royalBlue.withAlpha(51)
                          : Brand.royalBlue.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Voice / document / location
                    if (msgType == 'voice' ||
                        msgType == 'document' ||
                        msgType == 'location')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: buildChatAttachment(
                              messageType: msgType,
                              attachments: attachments == null
                                  ? const []
                                  : List<String>.from(
                                      attachments.map((e) => e.toString())),
                              metadata: message['metadata'] is Map
                                  ? Map<String, dynamic>.from(
                                      message['metadata'] as Map)
                                  : null,
                              isMe: isMyMessage,
                              accent:
                                  isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                            ) ??
                            const SizedBox.shrink(),
                      ),
                    // Attachments (images / files)
                    if (msgType != 'voice' &&
                        msgType != 'document' &&
                        msgType != 'location' &&
                        attachments != null &&
                        attachments.isNotEmpty) ...[
                      ...attachments.map((url) {
                        final urlStr = url.toString();
                        if (_isImageUrl(urlStr)) {
                          return GestureDetector(
                            onTap: () => _showFullImage(urlStr, isDark),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              constraints: const BoxConstraints(
                                  maxHeight: 200, maxWidth: 250),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: CachedNetworkImage(
                                  imageUrl: urlStr,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Brand.darkCardElevated
                                          : Brand.royalBlueSurface,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: isDark
                                            ? Brand.royalBlueGlow
                                            : Brand.royalBlue,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    height: 60,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Brand.darkCardElevated
                                          : Brand.royalBlueSurface,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image_rounded,
                                            size: 20,
                                            color: isDark
                                                ? Brand.darkTextSecondary
                                                : Brand.subtleLight),
                                        const SizedBox(width: 8),
                                        Text('Image failed',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? Brand.darkTextSecondary
                                                    : Brand.subtleLight)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        } else {
                          return GestureDetector(
                            onTap: () => _launchUrl(urlStr),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isMyMessage
                                    ? Colors.white.withAlpha(20)
                                    : (isDark
                                        ? Brand.darkCardElevated
                                        : Brand.royalBlueSurface),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded,
                                      size: 18,
                                      color: isMyMessage
                                          ? Colors.white70
                                          : (isDark
                                              ? Brand.royalBlueGlow
                                              : Brand.royalBlue)),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      urlStr.split('/').last,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMyMessage
                                            ? Colors.white70
                                            : (isDark
                                                ? Brand.royalBlueGlow
                                                : Brand.royalBlue),
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }),
                    ],

                    // Message text
                    if (message['message'] != null &&
                        message['message'].toString().isNotEmpty &&
                        message['message'] != '📎 Image attached')
                      SelectableText(
                        message['message'],
                        style: TextStyle(
                          fontSize: 14,
                          color: isMyMessage
                              ? Colors.white
                              : (isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                    const SizedBox(height: 5),

                    // Footer
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isFailed)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 13, color: Colors.red),
                              SizedBox(width: 4),
                              Text('Failed · Tap to retry',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                            ],
                          )
                        else if (isSending)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: isMyMessage
                                      ? Colors.white38
                                      : (isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        Text(
                          _formatTime(timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: isMyMessage
                                ? Colors.white.withAlpha(115)
                                : (isDark ? Colors.white24 : Colors.black26),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isMyMessage && !isSending && !isFailed) ...[
                          const SizedBox(width: 4),
                          Builder(builder: (_) {
                            final isRead = message['is_read'] == true;
                            final delivered = message['delivered_at'] != null;
                            if (isRead) {
                              return const Icon(Icons.done_all_rounded,
                                  size: 14, color: Brand.lightGreenBright);
                            }
                            if (delivered) {
                              return Icon(Icons.done_all_rounded,
                                  size: 14,
                                  color: Colors.white.withAlpha(140));
                            }
                            return Icon(Icons.done_rounded,
                                size: 14, color: Colors.white.withAlpha(89));
                          }),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(Map<String, dynamic> message, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.copy_rounded,
                    color: isDark ? Colors.white60 : Brand.royalBlueDark,
                    size: 20),
              ),
              title: Text('Copy Message',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: message['message'] ?? ''));
                Navigator.pop(context);
                _showSuccessSnackBar('Message copied');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFullImage(String url, bool isDark) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _launchUrl(url),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── MESSAGE INPUT ─────────────────────────────────────────

  Widget _buildMessageInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
            top: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                width: 1)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('Uploading image...',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: _isUploading
                            ? Brand.royalBlue.withAlpha(20)
                            : (isDark
                                ? Brand.darkCardElevated
                                : Brand.scaffoldLight),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: isDark
                                ? Brand.darkBorderLight
                                : Brand.borderLight),
                      ),
                      child: Icon(
                        Icons.attach_file_rounded,
                        color: _isUploading
                            ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                            : (isDark ? Colors.white38 : Brand.subtleLight),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color:
                          isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontWeight: FontWeight.w500),
                      cursorColor:
                          isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                      decoration: InputDecoration(
                        hintText: S.of(context)!.ticketTypeMessage,
                        hintStyle: TextStyle(
                          color: isDark
                              ? Colors.white24
                              : Brand.subtleLight.withAlpha(153),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        enabledBorder: InputBorder.none,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                              color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                              width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isSendingMessage ? null : _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Brand.royalBlue, Brand.royalBlueLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(102),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
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
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── RATING PROMPT ─────────────────────────────────────────

  Widget _buildRatingPrompt(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
            top: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                width: 1)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Text('How was your experience?',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text('Rate our support to help us improve',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () => _showRatingDialog(i + 1, isDark),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.star_rounded,
                      size: 36,
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _reopenTicket(),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Text('Reopen Ticket',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRatingDialog(int initialRating, bool isDark) {
    int selectedRating = initialRating;
    final feedbackController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Brand.cardLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 22),
                Text('Rate Your Experience',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                        letterSpacing: -0.4)),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final rating = i + 1;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedRating = rating),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedScale(
                          scale: rating <= selectedRating ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            rating <= selectedRating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 42,
                            color: rating <= selectedRating
                                ? Colors.amber
                                : (isDark
                                    ? Brand.darkBorderLight
                                    : Brand.borderLight),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                Text(
                  [
                    '',
                    'Poor',
                    'Fair',
                    'Good',
                    'Very Good',
                    'Excellent'
                  ][selectedRating],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: feedbackController,
                  maxLines: 3,
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      fontWeight: FontWeight.w500),
                  cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  decoration: InputDecoration(
                    hintText: 'Share your feedback (optional)',
                    hintStyle: TextStyle(
                        color: isDark
                            ? Colors.white24
                            : Brand.subtleLight.withAlpha(153),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    filled: true,
                    fillColor:
                        isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _submitRating(
                        selectedRating,
                        feedbackController.text.trim().isNotEmpty
                            ? feedbackController.text.trim()
                            : null,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Brand.lightGreenDark, Brand.lightGreen],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Brand.lightGreen.withAlpha(89),
                              blurRadius: 14,
                              offset: const Offset(0, 5)),
                        ],
                      ),
                      child: const Center(
                        child: Text('Submit Rating',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── CLOSED BANNER ─────────────────────────────────────────

  Widget _buildClosedBanner(bool isDark) {
    final status = _ticket!['status'] ?? 'closed';
    final statusColor = _getStatusColor(status);
    final rating = _ticket!['customer_rating'] as int?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
            top: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                width: 1)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(((isDark ? 0.08 : 0.05) * 255).toInt()),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withAlpha(38)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    Icon(_getStatusIcon(status), color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket ${status == 'resolved' ? 'Resolved' : 'Closed'}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: i < rating
                                  ? Colors.amber
                                  : (isDark
                                      ? Brand.darkBorderLight
                                      : Brand.borderLight),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Your rating',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ] else
                      Text('This conversation has ended',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _reopenTicket,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Brand.royalBlue, Brand.royalBlueLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(89),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
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

  // ─── TICKET OPTIONS ────────────────────────────────────────

  void _showTicketOptions(bool isDark) {
    final isClosed = const {
      'resolved',
      'closed',
      'completed',
      'cancelled',
    }.contains(_ticket!['status']);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(24),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(S.of(context)!.ticketOptions,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.4)),
            const SizedBox(height: 16),
            _buildOptionItem(
              icon: Icons.refresh_rounded,
              label: S.of(context)!.ticketRefresh,
              color: Brand.royalBlueLight,
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _loadAllData();
              },
            ),
            _buildOptionItem(
              icon: Icons.info_outline_rounded,
              label: _isHeaderExpanded
                  ? S.of(context)!.ticketHideDetails
                  : S.of(context)!.ticketShowDetails,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlueDark,
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                setState(() => _isHeaderExpanded = !_isHeaderExpanded);
              },
            ),
            _buildOptionItem(
              icon: Icons.copy_rounded,
              label: S.of(context)!.ticketCopyNumber,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
              isDark: isDark,
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: _ticket!['ticket_number'] ?? ''));
                Navigator.pop(context);
                _showSuccessSnackBar('Copied: ${_ticket!['ticket_number']}');
              },
            ),
            if (_assignedEngineer?['phone_number'] != null)
              _buildOptionItem(
                icon: Icons.phone_rounded,
                label: S.of(context)!.ticketCallEngineer,
                color: Brand.lightGreen,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _launchUrl('tel:${_assignedEngineer!['phone_number']}');
                },
              ),
            _buildOptionItem(
              icon: Icons.phone_in_talk_rounded,
              label: S.of(context)!.ticketCallSupport,
              color: Brand.lightGreenBright,
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _launchUrl('tel:0777244882');
              },
            ),
            if (!isClosed)
              _buildOptionItem(
                icon: Icons.cancel_rounded,
                label: S.of(context)!.ticketClose,
                color: Colors.red,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _closeTicket();
                },
              ),
            if (isClosed)
              _buildOptionItem(
                icon: Icons.refresh_rounded,
                label: S.of(context)!.ticketReopen,
                color: Colors.orange,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _reopenTicket();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
      onTap: onTap,
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
                color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading older messages…',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.removeListener(_onChatScroll);
    _scrollController.dispose();
    _messageFocusNode.dispose();
    if (_chatChannel != null) {
      SupabaseConfig.client.removeChannel(_chatChannel!);
    }
    super.dispose();
  }
}
