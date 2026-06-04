import 'package:flutter/material.dart';

/// Skeleton loader for cards and list items.
/// Shows a shimmer animation while content loads.
class SkeletonCard extends StatelessWidget {
  final double? height;
  final double? width;
  final BorderRadius borderRadius;

  const SkeletonCard({
    super.key,
    this.height = 100,
    this.width = double.infinity,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerWidget(
      height: height ?? 100,
      width: width,
      borderRadius: borderRadius,
    );
  }
}

/// Skeleton loader for text lines (multi-line support).
class SkeletonText extends StatelessWidget {
  final int lines;
  final double height;
  final double spacing;

  const SkeletonText({
    super.key,
    this.lines = 2,
    this.height = 12,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        lines,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < lines - 1 ? spacing : 0),
          child: ShimmerWidget(
            height: height,
            width: i < lines - 1
                ? double.infinity
                : 0.7 * MediaQuery.of(context).size.width,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Skeleton loader for list items (mimics card + text).
class SkeletonListItem extends StatelessWidget {
  final double? height;

  const SkeletonListItem({super.key, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Avatar placeholder
          ShimmerWidget(
            height: 50,
            width: 50,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 12),
          // Text lines
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerWidget(
                  height: 12,
                  width: 0.6 * MediaQuery.of(context).size.width,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                ShimmerWidget(
                  height: 10,
                  width: 0.4 * MediaQuery.of(context).size.width,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Base shimmer widget that creates the loading animation.
class ShimmerWidget extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;
  final Duration animationDuration;

  const ShimmerWidget({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.animationDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            color: Colors.grey.shade200,
          ),
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1 + _shimmerAnimation.value, 0),
                end: Alignment(_shimmerAnimation.value, 0),
                colors: [
                  Colors.grey.shade200,
                  Colors.grey.shade100,
                  Colors.grey.shade200,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: Container(
              height: widget.height,
              width: widget.width,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                color: Colors.grey.shade300,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton screen for dashboard sections.
class SkeletonSection extends StatelessWidget {
  final String title;
  final int itemCount;
  final bool isList;

  const SkeletonSection({
    super.key,
    required this.title,
    this.itemCount = 3,
    this.isList = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title skeleton
        SkeletonText(lines: 1, height: 16),
        const SizedBox(height: 12),
        // Items
        ...List.generate(
          itemCount,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i < itemCount - 1 ? 12 : 0),
            child: isList ? SkeletonListItem() : SkeletonCard(height: 100),
          ),
        ),
      ],
    );
  }
}
