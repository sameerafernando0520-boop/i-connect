import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../../models/chat_message.dart';
import '../../../utils/time_utils.dart';
import '../../common/chat_message_attachments.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isSelf;
  final bool showDateSeparator;
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    this.showDateSeparator = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDateSeparator) _buildDateSeparator(context),
        if (message.senderType == 'system')
          _buildSystemMessage(context)
        else
          _buildChatBubble(context),
      ],
    );
  }

  // ─── DATE SEPARATOR ──────────────────────────────
  Widget _buildDateSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: Divider(color: AdminColors.border(context), height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              TimeUtils.formatDateSeparator(message.createdAt),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AdminColors.textHint(context),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
              child: Divider(color: AdminColors.border(context), height: 1)),
        ],
      ),
    );
  }

  // ─── SYSTEM MESSAGE ──────────────────────────────
  Widget _buildSystemMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 13, color: AdminColors.textHint(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message.message,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AdminColors.textHint(context),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CHAT BUBBLE ─────────────────────────────────
  Widget _buildChatBubble(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFailed = message.status == MessageStatus.failed;
    final isSending = message.status == MessageStatus.sending;

    // Colors
    final Color bubbleColor;
    final Color textColor;

    if (isSelf) {
      bubbleColor = AdminColors.primary;
      textColor = Colors.white;
    } else {
      bubbleColor =
          isDark ? AdminColors.cardElevated(context) : AdminColors.background;
      textColor = AdminColors.text(context);
    }

    return Opacity(
      opacity: isSending ? 0.7 : 1.0,
      child: Align(
        alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            top: 4,
            bottom: 4,
            left: isSelf ? 60 : 0,
            right: isSelf ? 0 : 60,
          ),
          child: Column(
            crossAxisAlignment:
                isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Sender name (left-aligned messages only)
              if (!isSelf && message.senderName != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAvatar(context),
                      const SizedBox(width: 6),
                      Text(
                        message.senderName!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _senderColor(),
                        ),
                      ),
                      if (message.senderType == 'engineer') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.engineering_rounded,
                            size: 11, color: AdminColors.info),
                      ],
                    ],
                  ),
                ),

              // Bubble
              GestureDetector(
                onTap: isFailed ? onRetry : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isSelf ? 18 : 4),
                      bottomRight: Radius.circular(isSelf ? 4 : 18),
                    ),
                    border: message.isInternal
                        ? Border(
                            left: BorderSide(
                                color: AdminColors.internal, width: 3))
                        : isFailed
                            ? Border.all(
                                color: AdminColors.error.withAlpha(100))
                            : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Internal badge
                      if (message.isInternal)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded,
                                  size: 10, color: AdminColors.internal),
                              const SizedBox(width: 3),
                              Text(
                                'Internal Note',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.internal,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Message text (hide placeholder when only attachments)
                      if (message.message.isNotEmpty &&
                          message.message != '📎 Image attached')
                        Text(
                          message.message,
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            height: 1.4,
                          ),
                        ),

                      // Attachments
                      if (message.messageType == 'voice' ||
                          message.messageType == 'document' ||
                          message.messageType == 'location')
                        buildChatAttachment(
                              messageType: message.messageType,
                              attachments: message.attachments,
                              metadata: message.metadata,
                              isMe: isSelf,
                              accent: AdminColors.primary,
                            ) ??
                            const SizedBox.shrink()
                      else if (message.attachments.isNotEmpty) ...[
                        if (message.message.isNotEmpty &&
                            message.message != '📎 Image attached')
                          const SizedBox(height: 8),
                        ...message.attachments.map(
                          (url) => _buildAttachmentImage(context, url),
                        ),
                      ],

                      const SizedBox(height: 4),

                      // Time + status row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            TimeUtils.formatMessageTime(message.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelf
                                  ? Colors.white.withAlpha(180)
                                  : AdminColors.textHint(context),
                            ),
                          ),
                          if (isSelf) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Failed hint
              if (isFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 12, color: AdminColors.error),
                      const SizedBox(width: 3),
                      Text(
                        'Tap to retry',
                        style:
                            TextStyle(fontSize: 11, color: AdminColors.error),
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

  // ─── HELPERS ─────────────────────────────────────
  Widget _buildAttachmentImage(BuildContext context, String url) {
    return GestureDetector(
      onTap: () => _openImageViewer(context, url),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 200,
            height: 150,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 200,
              height: 150,
              color: Colors.black12,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 200,
              height: 60,
              decoration: BoxDecoration(
                color: AdminColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_rounded,
                      color: AdminColors.error, size: 18),
                  const SizedBox(width: 6),
                  Text('Image unavailable',
                      style: TextStyle(
                          fontSize: 12, color: AdminColors.error)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openImageViewer(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(
                    width: 80,
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white54,
                      size: 48),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final color = _senderColor();
    final initials = _getInitials(message.senderName);
    final photo = message.senderPhoto;
    const double size = 26;

    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        );

    if (photo == null || photo.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback(),
        errorWidget: (_, __, ___) => fallback(),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (message.status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Colors.white70),
        );
      case MessageStatus.failed:
        return Icon(Icons.close_rounded,
            size: 13, color: StatusColors.danger);
      case MessageStatus.sent:
        if (message.isRead) {
          return const Icon(Icons.done_all_rounded,
              size: 14, color: AdminColors.info);
        }
        if (message.deliveredAt != null) {
          return const Icon(Icons.done_all_rounded,
              size: 14, color: Colors.white70);
        }
        return const Icon(Icons.done_rounded,
            size: 14, color: Colors.white70);
    }
  }

  Color _senderColor() {
    switch (message.senderType) {
      case 'customer':
        return AdminColors.primary;
      case 'engineer':
        return AdminColors.info;
      case 'admin':
        return AdminColors.accent;
      default:
        return AdminColors.primary;
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}
