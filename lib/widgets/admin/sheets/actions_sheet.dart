import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';

class ActionItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const ActionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class ActionsSheet {
  static void show(
    BuildContext context, {
    required String title,
    required List<ActionItem> actions,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AdminColors.card(ctx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdminColors.border(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.text(ctx),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ...actions.map((action) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        action.onTap();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AdminColors.bg(ctx),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AdminColors.border(ctx)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: action.color.withAlpha(
                                  Theme.of(ctx).brightness == Brightness.dark
                                      ? 30
                                      : 15,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(action.icon,
                                  size: 20, color: action.color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    action.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(ctx),
                                    ),
                                  ),
                                  if (action.subtitle != null)
                                    Text(
                                      action.subtitle!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AdminColors.textSub(ctx),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 20, color: AdminColors.textHint(ctx)),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
