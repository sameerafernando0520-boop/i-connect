// lib/widgets/admin/section_label.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';

class SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget? trailing;

  const SectionLabel({
    super.key,
    required this.label,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AdminColors.primary.withAlpha(isDark ? 35 : 15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isDark ? Brand.darkIconActive : AdminColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
