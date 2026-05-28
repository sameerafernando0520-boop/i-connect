// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/chat_button.dart
// UPDATED v18 — Dark mode shadow adjustment
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';

class InquiryChatButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const InquiryChatButton({
    super.key,
    this.unreadCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2E7D32), const Color(0xFF558B2F)]
                : [AdminColors.accent, const Color(0xFF93A52E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AdminColors.accent.withAlpha(isDark ? 40 : 75),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Chat icon with badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(
                      Icons.chat_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AdminColors.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Center(
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chat with Customer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    unreadCount > 0
                        ? '$unreadCount unread message${unreadCount > 1 ? 's' : ''}'
                        : 'Send messages, quotes & updates',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
