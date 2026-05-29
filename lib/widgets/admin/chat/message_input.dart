import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../common/chat_attach_bar.dart';

class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isInternal;
  final bool isUploading;
  final VoidCallback onSend;
  final VoidCallback onToggleInternal;
  final VoidCallback? onAttachment;

  /// When [ticketId] + [onSendAttachment] are provided, the input shows a rich
  /// "+" attachment menu (image/document/location) and a hold-to-record voice
  /// button instead of the legacy single paperclip.
  final String? ticketId;
  final ChatSendAttachment? onSendAttachment;
  final Color? accent;

  const MessageInput({
    super.key,
    required this.controller,
    required this.isSending,
    required this.isInternal,
    this.isUploading = false,
    required this.onSend,
    required this.onToggleInternal,
    this.onAttachment,
    this.ticketId,
    this.onSendAttachment,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        border: Border(
          top: BorderSide(color: AdminColors.border(context), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Upload progress banner
          if (isUploading)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AdminColors.info.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AdminColors.info.withAlpha(50)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AdminColors.info),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Uploading image…',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.info,
                    ),
                  ),
                ],
              ),
            ),

          // Internal mode banner
          if (isInternal)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AdminColors.internal.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.internal.withAlpha(50)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded,
                      size: 13, color: AdminColors.internal),
                  const SizedBox(width: 6),
                  Text(
                    'Internal note — hidden from customer',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.internal,
                    ),
                  ),
                ],
              ),
            ),

          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attachment button — rich menu when wired, else legacy paperclip
              if (ticketId != null && onSendAttachment != null)
                ChatAttachMenuButton(
                  ticketId: ticketId!,
                  accent: accent ?? AdminColors.primary,
                  onSend: onSendAttachment!,
                )
              else
                _buildActionButton(
                  context,
                  icon: Icons.attach_file_rounded,
                  color: isUploading
                      ? AdminColors.info
                      : AdminColors.textHint(context),
                  onTap: isUploading ? null : onAttachment,
                ),
              const SizedBox(width: 4),

              // Internal toggle
              _buildActionButton(
                context,
                icon: isInternal ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: isInternal
                    ? AdminColors.internal
                    : AdminColors.textHint(context),
                onTap: onToggleInternal,
              ),
              const SizedBox(width: 8),

              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: AdminColors.bg(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isInternal
                          ? AdminColors.internal.withAlpha(60)
                          : AdminColors.border(context),
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    maxLines: 5,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontSize: 14,
                      color: AdminColors.text(context),
                    ),
                    decoration: InputDecoration(
                      hintText: isInternal
                          ? 'Write internal note...'
                          : 'Type a message...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: AdminColors.textHint(context),
                      ),
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: isDark ? Brand.darkIconActive : AdminColors.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Voice recorder (hold to record) — when wired
              if (ticketId != null && onSendAttachment != null)
                ChatVoiceRecorderButton(
                  ticketId: ticketId!,
                  accent: accent ?? AdminColors.primary,
                  onSend: onSendAttachment!,
                ),

              // Send button
              GestureDetector(
                onTap: isSending ? null : onSend,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color:
                        isInternal ? AdminColors.internal : AdminColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: isSending
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}
