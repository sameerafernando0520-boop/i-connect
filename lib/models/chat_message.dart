// lib/models/chat_message.dart

enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final String? id;
  final String ticketId;
  final String senderId;
  final String senderType;
  final String message;
  final List<String> attachments;
  final bool isInternal;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final MessageStatus status;
  final String? senderName;
  final String? senderPhoto;

  /// text | image | document | voice | location
  final String messageType;

  /// Type-specific extras, e.g. {duration_ms} for voice,
  /// {lat,lng,label} for location, {filename,size} for document.
  final Map<String, dynamic>? metadata;

  ChatMessage({
    this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderType,
    required this.message,
    this.attachments = const [],
    this.isInternal = false,
    this.isRead = false,
    this.readAt,
    this.deliveredAt,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.senderName,
    this.senderPhoto,
    this.messageType = 'text',
    this.metadata,
  });

  // M12: Whitelist of server-recognized sender roles. Anything else we see on
  // the wire (typo, newly added role the client doesn't understand, tampered
  // payload) collapses to 'customer' — the least-privileged default — so a
  // rogue value can't grant admin-styling affordances in the UI.
  static const Set<String> _allowedSenderTypes = {
    'customer',
    'admin',
    'engineer',
    'system',
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final sender = j['sender'] as Map<String, dynamic>?;

    // M12: Enum-check sender_type. A malformed row shouldn't render as a
    // styled admin bubble or break the switch statements downstream.
    final rawType = (j['sender_type'] as String?) ?? 'customer';
    final senderType =
        _allowedSenderTypes.contains(rawType) ? rawType : 'customer';

    // M12: Attachments can arrive as null, a JSON list, or (bug path) a
    // stringified array. Guard the `List.from` call so a bad shape doesn't
    // throw and nuke the whole chat stream.
    final rawAttachments = j['attachments'];
    final attachments = rawAttachments is List
        ? List<String>.from(
            rawAttachments.whereType<Object>().map((e) => e.toString()))
        : const <String>[];

    // M12: `created_at` is effectively required for ordering, but a bad row
    // shouldn't crash the model — fall back to `now` and log so the
    // regression is visible in telemetry.
    final created = DateTime.tryParse(j['created_at']?.toString() ?? '') ??
        DateTime.now();

    return ChatMessage(
      id: j['id']?.toString(),
      ticketId: (j['ticket_id'] as Object?)?.toString() ?? '',
      senderId: (j['sender_id'] as Object?)?.toString() ?? '',
      senderType: senderType,
      message: (j['message'] as String?) ?? '',
      attachments: attachments,
      isInternal: j['is_internal'] == true,
      isRead: j['is_read'] == true,
      readAt: DateTime.tryParse(j['read_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(j['delivered_at']?.toString() ?? ''),
      createdAt: created,
      status: MessageStatus.sent,
      senderName: sender?['full_name'] as String?,
      senderPhoto: sender?['profile_photo'] as String?,
      messageType: (j['message_type'] as String?) ?? 'text',
      metadata: j['metadata'] is Map
          ? Map<String, dynamic>.from(j['metadata'] as Map)
          : null,
    );
  }

  factory ChatMessage.optimistic({
    required String ticketId,
    required String senderId,
    required String message,
    bool isInternal = false,
    List<String> attachments = const [],
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) =>
      ChatMessage(
        ticketId: ticketId,
        senderId: senderId,
        senderType: 'admin',
        message: message,
        attachments: attachments,
        isInternal: isInternal,
        createdAt: DateTime.now(),
        status: MessageStatus.sending,
        messageType: messageType,
        metadata: metadata,
      );

  ChatMessage copyWith({
    MessageStatus? status,
    String? id,
    String? senderName,
    String? senderPhoto,
    bool? isRead,
    DateTime? readAt,
    DateTime? deliveredAt,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        ticketId: ticketId,
        senderId: senderId,
        senderType: senderType,
        message: message,
        attachments: attachments,
        isInternal: isInternal,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        createdAt: createdAt,
        status: status ?? this.status,
        senderName: senderName ?? this.senderName,
        senderPhoto: senderPhoto ?? this.senderPhoto,
        messageType: messageType,
        metadata: metadata,
      );
}
