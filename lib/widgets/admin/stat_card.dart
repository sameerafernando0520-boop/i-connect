// lib/widgets/admin/stat_card.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';

class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final bool trendPositive;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
    this.trendPositive = true,
    this.onTap,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? widget.color.withAlpha(40)
                  : widget.color.withAlpha(51),
              width: 1,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: widget.color.withAlpha(20),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Subtle background glow matching the card color
              Positioned(
                right: -10,
                bottom: -10,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.color.withAlpha(isDark ? 25 : 15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Premium Icon Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color.withAlpha(isDark ? 50 : 35),
                              widget.color.withAlpha(isDark ? 25 : 15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.color.withAlpha(isDark ? 60 : 40),
                            width: 1,
                          ),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 28),
                      ),
                      // Trend or Action indicator
                      if (widget.trend != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (widget.trendPositive
                                    ? AdminColors.success
                                    : AdminColors.error)
                                .withAlpha(isDark ? 30 : 20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (widget.trendPositive
                                      ? AdminColors.success
                                      : AdminColors.error)
                                  .withAlpha(isDark ? 50 : 40),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.trendPositive
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                size: 14,
                                color: widget.trendPositive
                                    ? AdminColors.success
                                    : AdminColors.error,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.trend!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: widget.trendPositive
                                      ? AdminColors.success
                                      : AdminColors.error,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? Brand.darkBg : Brand.scaffoldLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Brand.darkBorder : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: isDark
                                ? Brand.darkIconActive
                                : AdminColors.primary.withAlpha(150),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Value and Title
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : AdminColors.primaryDark,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : AdminColors.textHint(context),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
