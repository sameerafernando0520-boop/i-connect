import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';

class QuickReplyBar extends StatelessWidget {
  final List<String> replies;
  final ValueChanged<String> onSelect;
  final VoidCallback? onClose;

  const QuickReplyBar({
    super.key,
    required this.replies,
    required this.onSelect,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        border: Border(
          top: BorderSide(color: AdminColors.border(context), width: 0.5),
          bottom: BorderSide(color: AdminColors.border(context), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded,
                  size: 14, color: AdminColors.primary),
              const SizedBox(width: 4),
              Text(
                'Quick Replies',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close_rounded,
                      size: 18, color: AdminColors.textHint(context)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: replies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                return GestureDetector(
                  onTap: () => onSelect(replies[i]),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withAlpha(
                        Theme.of(context).brightness == Brightness.dark
                            ? 30
                            : 12,
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border:
                          Border.all(color: AdminColors.primary.withAlpha(40)),
                    ),
                    child: Text(
                      replies[i],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AdminColors.primary,
                      ),
                      maxLines: 1,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
