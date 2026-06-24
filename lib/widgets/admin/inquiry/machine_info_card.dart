// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/machine_info_card.dart
// UPDATED v18 — Full dark mode, CachedNetworkImage
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../../models/inquiry_detail.dart';
import '../section_label.dart';

class MachineInfoCard extends StatelessWidget {
  final InquiryMachine machine;

  const MachineInfoCard({super.key, required this.machine});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(
            label: 'Interested Machine',
            icon: Icons.precision_manufacturing_rounded,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : AdminColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Brand.surface(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                  ),
                  child: machine.hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: machine.imageUrl!,
                            fit: BoxFit.cover,
                            width: 64,
                            height: 64,
                            placeholder: (_, __) => Icon(
                              Icons.inventory_2_rounded,
                              size: 28,
                              color: isDark
                                  ? Brand.darkIconActive
                                  : AdminColors.primary,
                            ),
                            errorWidget: (_, __, ___) => Icon(
                              Icons.inventory_2_rounded,
                              size: 28,
                              color: isDark
                                  ? Brand.darkIconActive
                                  : AdminColors.primary,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.inventory_2_rounded,
                          size: 28,
                          color: isDark
                              ? Brand.darkIconActive
                              : AdminColors.primary,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (machine.brand != null)
                            _buildTag(
                              machine.brand!,
                              AdminColors.primary,
                              isDark,
                            ),
                          if (machine.category != null) ...[
                            const SizedBox(width: 6),
                            _buildTag(
                              machine.category!,
                              AdminColors.accent,
                              isDark,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        machine.machineName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.darkCard,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (machine.modelNumber != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          machine.modelNumber!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (machine.description != null &&
              machine.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              machine.description!,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSecondary,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 31 : 15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
