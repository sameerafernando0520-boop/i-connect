// lib/widgets/customer/customer_nav_bar.dart
// v24 — Customer bottom nav bar with refined micro-animations
//
// Indices:  0 = Home  |  1 = Machines  |  2 = Support (FAB)  |  3 = Knowledge
//           4 = Profile
//
// Animation upgrades vs v23:
//   • Selected pill grows with `Curves.easeOutBack` for a small bounce.
//   • Icon scales up ~1.12× on selection, then settles back to 1.0×.
//   • Selected label gets a soft slide-up.
//   • Center FAB icon bounces on tap via scale tween.

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../widgets/common/ic_icons.dart';

class CustomerNavBar extends StatelessWidget {
  final int currentIndex;
  final int openTickets;
  final void Function(int) onTabSelected;

  const CustomerNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.openTickets = 0,
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
        border: isDark
            ? const Border(
                top: BorderSide(color: Brand.darkBorder, width: 1),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(80)
                : Brand.royalBlue.withAlpha(12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _AnimatedNavItem(
                selected: currentIndex == 0,
                onTap: () => onTabSelected(0),
                isDark: isDark,
                label: 'Home',
                builder: (c) => Icon(Icons.home_rounded, color: c, size: 24),
              ),
              _AnimatedNavItem(
                selected: currentIndex == 1,
                onTap: () => onTabSelected(1),
                isDark: isDark,
                label: 'Machines',
                builder: (c) => IcTwinGearIcon(
                  primaryColor: c,
                  secondaryColor: currentIndex == 1
                      ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                      : (isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                  size: 24,
                ),
              ),
              _navCenter(context, isDark),
              _AnimatedNavItem(
                selected: currentIndex == 3,
                onTap: () => onTabSelected(3),
                isDark: isDark,
                label: 'Knowledge',
                builder: (c) =>
                    Icon(Icons.auto_stories_rounded, color: c, size: 24),
              ),
              _AnimatedNavItem(
                selected: currentIndex == 4,
                onTap: () => onTabSelected(4),
                isDark: isDark,
                label: 'Profile',
                builder: (c) => Icon(Icons.person_rounded, color: c, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Center FAB — bouncy scale on tap + badge ─────────────────────────────
  Widget _navCenter(BuildContext context, bool isDark) {
    final isSel = currentIndex == 2;
    return _BounceTap(
      onTap: () {
        if (!isSel) onTabSelected(2);
      },
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkIconActive, Brand.royalBlueGlow]
                  : [Brand.royalBlue, Brand.royalBlueLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Brand.darkIconActive.withAlpha(isSel ? 100 : 60)
                    : Brand.royalBlue.withAlpha(isSel ? 140 : 90),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(child: IcChatGearIcon(color: Colors.white, size: 28)),
        ),
        if (openTickets > 0)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF4757), Color(0xFFFF6B81)],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Brand.darkCard : Colors.white,
                  width: 2.5,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              child: Center(
                child: Text(
                  openTickets > 9 ? '9+' : '$openTickets',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated nav item — selected state animates with easeOutBack pill grow and
// a small icon scale punch.  Tap also triggers a subtle scale-down feedback.
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedNavItem extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final String label;
  final Widget Function(Color color) builder;

  const _AnimatedNavItem({
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.label,
    required this.builder,
  });

  @override
  State<_AnimatedNavItem> createState() => _AnimatedNavItemState();
}

class _AnimatedNavItemState extends State<_AnimatedNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isDark
        ? Brand.darkIconActive
        : Brand.royalBlue;
    final idleColor = widget.isDark
        ? Brand.darkTextTertiary
        : Brand.subtleLight;
    final iconColor = widget.selected ? activeColor : idleColor;

    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: ScaleTransition(
          scale: _pressScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pill that grows with a small bounce when selected.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: widget.selected ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                builder: (_, t, child) {
                  final pillColor = (widget.isDark
                          ? Brand.darkIconActive
                          : Brand.royalBlue)
                      .withAlpha((t * (widget.isDark ? 38 : 28)).round());
                  // Pill expands horizontally + icon scales 1.0 → 1.12.
                  final scale = 1.0 + (0.12 * t);
                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10 + 6 * t,
                      vertical: 6 + 2 * t,
                    ),
                    decoration: BoxDecoration(
                      color: pillColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: widget.builder(iconColor),
              ),
              const SizedBox(height: 3),
              // Label fades in weight + lifts subtly on selection.
              AnimatedSlide(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                offset: widget.selected
                    ? const Offset(0, -0.05)
                    : Offset.zero,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                    color: widget.selected ? activeColor : idleColor,
                    letterSpacing: widget.selected ? 0.1 : 0,
                  ),
                  child: Text(widget.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bouncy tap wrapper used by the center FAB ────────────────────────────────
class _BounceTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BounceTap({required this.child, required this.onTap});
  @override
  State<_BounceTap> createState() => _BounceTapState();
}

class _BounceTapState extends State<_BounceTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _s;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 110),
        reverseDuration: const Duration(milliseconds: 220));
    _s = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(scale: _s, child: widget.child),
    );
  }
}
