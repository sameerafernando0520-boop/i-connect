// lib/widgets/admin/inquiry_card.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../models/dashboard_stats.dart';
import '../../utils/time_utils.dart';

class InquiryCard extends StatelessWidget {
  final RecentInquiry inquiry;
  final VoidCallback? onTap;

  const InquiryCard({
    super.key,
    required this.inquiry,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = AdminColors.statusColor(inquiry.status);
    final timeAgo = TimeUtils.getTimeAgo(inquiry.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminColors.card(context),
          borderRadius: BorderRadius.circular(AdminDimens.cardRadius),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Status bar
            Container(
              width: 4,
              height: 70,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tags row
                  Row(
                    children: [
                      _buildTag('INQUIRY', AdminColors.info, isDark),
                      const SizedBox(width: 6),
                      _buildTag(
                          inquiry.status.toUpperCase(), statusColor, isDark),
                      if (inquiry.priority == 'urgent') ...[
                        const SizedBox(width: 6),
                        _buildTag('URGENT', AdminColors.error, isDark),
                      ],
                      const Spacer(),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Title
                  Text(
                    inquiry.displayTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.text(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Customer info
                  Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 13,
                        color: AdminColors.textHint(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        inquiry.customerName ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context),
                        ),
                      ),
                      if (inquiry.companyName != null) ...[
                        const SizedBox(width: 8),
                        _dot(context),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            inquiry.companyName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AdminColors.textSub(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildArrow(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 35 : 25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _dot(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: AdminColors.textHint(context),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildArrow(BuildContext context, bool isDark) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkBg : AdminColors.bg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 12,
        color: isDark ? Brand.darkIconActive : AdminColors.primary,
      ),
    );
  }
}

