// lib/widgets/admin/customer_card.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../models/dashboard_stats.dart';
import '../../utils/time_utils.dart';

class CustomerCard extends StatelessWidget {
  final RecentCustomer customer;
  final VoidCallback? onTap;

  const CustomerCard({
    super.key,
    required this.customer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeAgo = TimeUtils.getTimeAgo(customer.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminColors.card(context),
          borderRadius: BorderRadius.circular(14),
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
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AdminColors.primary.withAlpha(isDark ? 35 : 20),
                    AdminColors.accent.withAlpha(isDark ? 35 : 20),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  customer.initials,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkIconActive : AdminColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.fullName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          customer.companyName ?? 'N/A',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSub(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AdminColors.textHint(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBg : AdminColors.bg(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: isDark ? Brand.darkIconActive : AdminColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
