// lib/widgets/admin/shimmer_loading.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';

class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
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

    // Dark mode: subtle dark shimmer — Light mode: classic grey shimmer
    final baseColor = isDark ? Brand.darkCardElevated : const Color(0xFFEEEEEE);
    final highlightColor =
        isDark ? Brand.darkBorderLight : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [baseColor, highlightColor, baseColor],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

// ── Skeleton Placeholder ──

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Dashboard Skeleton ──

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const SkeletonBox(width: 48, height: 48, radius: 14),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 120, height: 18, radius: 6),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 14, radius: 6),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Banner card
            const SkeletonBox(width: double.infinity, height: 180, radius: 20),
            const SizedBox(height: 20),
            // Stats grid
            const Row(
              children: [
                Expanded(child: SkeletonBox(width: 0, height: 120, radius: 16)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(width: 0, height: 120, radius: 16)),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: SkeletonBox(width: 0, height: 120, radius: 16)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(width: 0, height: 120, radius: 16)),
              ],
            ),
            const SizedBox(height: 24),
            // List items
            const SkeletonBox(width: 120, height: 16, radius: 6),
            const SizedBox(height: 14),
            for (int i = 0; i < 3; i++) ...[
              const SkeletonBox(width: double.infinity, height: 80, radius: 14),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
