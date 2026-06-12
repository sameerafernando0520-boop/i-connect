// Design-system widgets for the "Navy Glow" look.
//
// Every role home shares the same anatomy:
//   DsHero        — radial splash-navy header, dot grid, greeting + lime
//                   hairline, optional trailing widget and "act now" card
//   DsHeroCard    — the frosted navy card inside the hero
//   DsStatRow     — stat tiles that overlap the hero's bottom edge
//   DsStatTile    — icon squircle + big numeral + quiet label
//
// The hero deliberately uses the splash navy constants (not the theme) in
// BOTH light and dark mode — it is the brand signature, mirroring the
// animated splash. Tiles and everything below follow the active theme.

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';

class DsHero extends StatelessWidget {
  final String greeting;
  final String title;
  final Widget? trailing;
  final Widget? actionCard;
  final EdgeInsets padding;

  const DsHero({
    super.key,
    required this.greeting,
    required this.title,
    this.trailing,
    this.actionCard,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 40),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.2),
          radius: 1.6,
          colors: [
            Brand.splashNavyGlow,
            Brand.splashNavyCore,
            Brand.splashNavyEdge,
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: CustomPaint(
        painter: _DotGridPainter(),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              color: Color(0xFF8FA3C8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const DsLimeLine(),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                if (actionCard != null) ...[
                  const SizedBox(height: 14),
                  actionCard!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lime hairline from the splash — the brand signature.
class DsLimeLine extends StatelessWidget {
  final double width;
  const DsLimeLine({super.key, this.width = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          colors: [Brand.lime, Brand.lime.withAlpha(64)],
        ),
      ),
    );
  }
}

/// Frosted navy card inside the hero ("act now" slot).
class DsHeroCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const DsHeroCard({
    super.key,
    required this.icon,
    required this.label,
    required this.title,
    this.iconColor = Brand.lime,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xD916294F),
            border: Border.all(color: const Color(0xFF2A3F6E)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(36),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8FA3C8),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: Color(0xFF5B6F99)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stat tiles row that overlaps the hero's curved bottom edge.
class DsStatRow extends StatelessWidget {
  final List<DsStatTile> tiles;
  final double overlap;

  const DsStatRow({super.key, required this.tiles, this.overlap = 26});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -overlap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class DsStatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const DsStatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark ? Brand.darkBorder : const Color(0xFFE4E9F2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 38 : 24),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.15,
                  color: isDark ? Brand.darkTextPrimary : const Color(0xFF0F2557),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular avatar with role-accent ring, for the hero's trailing slot.
class DsHeroAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final String? photoUrl;
  final VoidCallback? onTap;

  const DsHeroAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.photoUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white.withAlpha(64), width: 2),
          image: photoUrl != null && photoUrl!.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(photoUrl!), fit: BoxFit.cover)
              : null,
        ),
        alignment: Alignment.center,
        child: photoUrl == null || photoUrl!.isEmpty
            ? Text(
                initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withAlpha(8);
    const step = 20.0;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}
