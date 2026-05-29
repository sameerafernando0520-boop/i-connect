import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/common/ic_icons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminNavBar — shared bottom navigation for admin tab-destination screens
//
// Indices:  0 = Dashboard  |  1 = Inquiries  |  2 = center (+)
//           3 = Tickets    |  4 = More
//
// Usage:
//   bottomNavigationBar: AdminNavBar(
//     currentIndex: 1,
//     onTabSelected: (idx) { ... },
//   ),
// ─────────────────────────────────────────────────────────────────────────────

class AdminNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTabSelected;

  /// Optional override for the center FAB tap (Quick Create).
  /// If null, tapping the center button does nothing on sub-pages.
  final VoidCallback? onCenterTap;

  /// Live badge counts (optional)
  final int inquiriesBadge;
  final int ticketsBadge;

  const AdminNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.onCenterTap,
    this.inquiriesBadge = 0,
    this.ticketsBadge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
          top: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(102)
                : AdminColors.primary.withAlpha(18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _navItem(
                  context,
                  (c) => Icon(Icons.dashboard_rounded, color: c, size: 24),
                  'Dashboard',
                  0,
                  isDark,
                ),
              ),
              Expanded(
                child: _navItemBadged(
                  context,
                  (c) => Icon(Icons.mail_rounded, color: c, size: 24),
                  'Inquiries',
                  1,
                  isDark,
                  badge: inquiriesBadge,
                ),
              ),
              _navCenter(context, isDark),
              Expanded(
                child: _navItemBadged(
                  context,
                  (c) => IcTicketIcon(color: c, size: 24),
                  'Tickets',
                  3,
                  isDark,
                  badge: ticketsBadge,
                ),
              ),
              Expanded(
                child: _navItem(
                  context,
                  (c) => Icon(Icons.grid_view_rounded, color: c, size: 24),
                  'More',
                  4,
                  isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navCenter(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: onCenterTap ?? () {},
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Brand.royalBlue, Brand.royalBlueLight]
                : [AdminColors.primary, Brand.royalBlueLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Brand.royalBlue : AdminColors.primary)
                  .withAlpha(102),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    Widget Function(Color) iconBuilder,
    String label,
    int idx,
    bool isDark,
  ) =>
      _navItemBadged(context, iconBuilder, label, idx, isDark, badge: 0);

  Widget _navItemBadged(
    BuildContext context,
    Widget Function(Color) iconBuilder,
    String label,
    int idx,
    bool isDark, {
    int badge = 0,
  }) {
    final sel = currentIndex == idx;
    final iconColor = sel
        ? (isDark ? Brand.royalBlueGlow : AdminColors.primary)
        : (isDark ? Brand.darkTextTertiary : Colors.grey.shade400);

    return GestureDetector(
      onTap: () {
        if (!sel) onTabSelected(idx);
      },
      behavior: HitTestBehavior.opaque,
      // FIX: full-width transparent hit area so taps anywhere in the
      // Expanded cell register — Column(mainAxisSize.min) alone gives
      // the GestureDetector a tap area only as wide as the icon+label.
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sel
                      ? (isDark
                          ? Brand.royalBlue.withAlpha(38)
                          : AdminColors.primary.withAlpha(26))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: iconBuilder(iconColor),
              ),
              if (badge > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AdminColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Brand.darkCard : Brand.cardLight,
                        width: 1.5,
                      ),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Center(
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel
                  ? (isDark ? Brand.royalBlueGlow : AdminColors.primary)
                  : (isDark ? Brand.darkTextTertiary : Colors.grey.shade400),
              letterSpacing: sel ? 0.1 : 0,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
