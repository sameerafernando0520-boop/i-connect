// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/inquiry_details_card.dart
// UPDATED v18 — Full dark mode pass
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../../models/inquiry_detail.dart';
import '../../../utils/time_utils.dart';
import '../section_label.dart';

class InquiryDetailsCard extends StatelessWidget {
  final InquiryDetail inquiry;

  const InquiryDetailsCard({super.key, required this.inquiry});

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
            label: 'Inquiry Details',
            icon: Icons.info_outline_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            icon: Icons.confirmation_number_rounded,
            label: 'Inquiry #',
            value: inquiry.ticketNumber,
            isDark: isDark,
          ),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Received',
            value: TimeUtils.formatDateTime(inquiry.createdAt),
            isDark: isDark,
          ),
          _DetailRow(
            icon: Icons.circle,
            label: 'Status',
            value: inquiry.status.toUpperCase().replaceAll('_', ' '),
            valueColor: AdminColors.statusColor(inquiry.status),
            isDark: isDark,
          ),
          if (inquiry.quantity != null)
            _DetailRow(
              icon: Icons.production_quantity_limits_rounded,
              label: 'Quantity',
              value: '${inquiry.quantity}',
              isDark: isDark,
            ),
          if (inquiry.deliveryAddress != null &&
              inquiry.deliveryAddress!.isNotEmpty)
            _DetailRow(
              icon: Icons.location_on_rounded,
              label: 'Delivery',
              value: inquiry.deliveryAddress ?? '',
              isDark: isDark,
            ),
          if (inquiry.additionalRequirements != null &&
              inquiry.additionalRequirements!.isNotEmpty)
            _DetailRow(
              icon: Icons.description_rounded,
              label: 'Requirements',
              value: inquiry.additionalRequirements ?? '',
              isDark: isDark,
            ),
          if (inquiry.quoteSentDate != null)
            _DetailRow(
              icon: Icons.receipt_long_rounded,
              label: 'Quote Sent',
              value: TimeUtils.formatDateFull(inquiry.quoteSentDate!),
              valueColor: AdminColors.accent,
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isDark;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AdminColors.primary.withAlpha(isDark ? 31 : 15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDark ? Brand.darkIconActive : AdminColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor ??
                        (isDark
                            ? Brand.darkTextPrimary
                            : const Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
