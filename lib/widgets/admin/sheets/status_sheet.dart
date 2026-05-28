import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';

class SelectionOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const SelectionOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class SelectionSheet {
  // ─── STATUS OPTIONS ──────────────────────────────
  static const List<SelectionOption> statusOptions = [
    SelectionOption(
        value: 'open',
        label: 'Open',
        icon: Icons.radio_button_unchecked_rounded,
        color: Color(0xFF2196F3)),
    SelectionOption(
        value: 'assigned',
        label: 'Assigned',
        icon: Icons.person_rounded,
        color: Color(0xFF9C27B0)),
    SelectionOption(
        value: 'in_progress',
        label: 'In Progress',
        icon: Icons.autorenew_rounded,
        color: Color(0xFFF57C00)),
    SelectionOption(
        value: 'waiting_customer',
        label: 'Waiting on Customer',
        icon: Icons.hourglass_top_rounded,
        color: Color(0xFFFF9800)),
    SelectionOption(
        value: 'resolved',
        label: 'Resolved',
        icon: Icons.check_circle_rounded,
        color: Color(0xFF43A047)),
    SelectionOption(
        value: 'closed',
        label: 'Closed',
        icon: Icons.lock_rounded,
        color: Color(0xFF607D8B)),
  ];

  // ─── PRIORITY OPTIONS ────────────────────────────
  static const List<SelectionOption> priorityOptions = [
    SelectionOption(
        value: 'urgent',
        label: 'Urgent',
        icon: Icons.priority_high_rounded,
        color: Color(0xFFE53935)),
    SelectionOption(
        value: 'high',
        label: 'High',
        icon: Icons.arrow_upward_rounded,
        color: Color(0xFFF57C00)),
    SelectionOption(
        value: 'medium',
        label: 'Medium',
        icon: Icons.remove_rounded,
        color: Color(0xFF2196F3)),
    SelectionOption(
        value: 'low',
        label: 'Low',
        icon: Icons.arrow_downward_rounded,
        color: Color(0xFF78909C)),
  ];

  // ─── SHOW SHEET ──────────────────────────────────
  static void show(
    BuildContext context, {
    required String title,
    required List<SelectionOption> options,
    required String currentValue,
    required ValueChanged<String> onSelect,
    String? confirmMessage,
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
                  if (confirmMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      confirmMessage,
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(ctx),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Options list
                  ...options.map((opt) {
                    final isSelected = opt.value == currentValue;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        if (opt.value != currentValue) {
                          onSelect(opt.value);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? opt.color.withAlpha(
                                  Theme.of(ctx).brightness == Brightness.dark
                                      ? 30
                                      : 15)
                              : AdminColors.bg(ctx),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: opt.color.withAlpha(60))
                              : Border.all(color: AdminColors.border(ctx)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: opt.color.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child:
                                  Icon(opt.icon, size: 18, color: opt.color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                opt.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AdminColors.text(ctx),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded,
                                  size: 20, color: opt.color),
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
