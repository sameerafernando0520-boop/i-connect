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

/// Tinted icon block — the shared squircle used across stat tiles and cards.
class DsIconSquircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  final double? iconSize;

  const DsIconSquircle({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.radius = 12,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 38 : 24),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize ?? size * 0.475, color: color),
    );
  }
}

/// Base card surface: white/dark, radius 16, hairline border, ink on tap.
class DsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final Color? borderColor;

  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(13),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.radius = 16,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              (isDark ? Brand.darkBorder : const Color(0xFFE4E9F2)),
        ),
      ),
      child: child,
    );
    final body = onTap == null && onLongPress == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(radius),
              child: card,
            ),
          );
    return margin == null ? body : Padding(padding: margin!, child: body);
  }
}

/// Standard list/action row: icon squircle + title/subtitle + trailing slot.
/// [footer] renders full-width under the row (progress bars, meta chips).
class DsActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets? margin;

  const DsActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.onTap,
    this.onLongPress,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DsCard(
      onTap: onTap,
      onLongPress: onLongPress,
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconSquircle(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : const Color(0xFF0F2557),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!]
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark ? Brand.darkTextTertiary : const Color(0xFFB6C0D4)),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 11), footer!],
        ],
      ),
    );
  }
}

/// THE single source of truth for status colors across the app.
/// Pass the raw status string plus an already-localized [label]
/// (never derive display text from the raw status here).
class DsStatusPill extends StatelessWidget {
  final String status;
  final String label;
  final Color? colorOverride;

  const DsStatusPill({
    super.key,
    required this.status,
    required this.label,
    this.colorOverride,
  });

  static Color colorFor(String status) {
    switch (status.toLowerCase().replaceAll(' ', '_')) {
      case 'open':
      case 'sent':
      case 'requested':
      case 'active':
        return StatusColors.open;
      case 'assigned':
      case 'confirmed':
      case 'refunded':
      case 'converted':
        return StatusColors.assigned;
      case 'in_progress':
      case 'partially_paid':
      case 'pending':
      case 'submitted':
      case 'medium':
      case 'service':
        return StatusColors.inProgress;
      case 'waiting_customer':
      case 'high':
        return StatusColors.waiting;
      case 'resolved':
      case 'paid':
      case 'accepted':
      case 'completed':
      case 'approved':
      case 'won':
        return StatusColors.success;
      case 'overdue':
      case 'rejected':
      case 'urgent':
      case 'escalated':
      case 'lost':
        return StatusColors.danger;
      case 'viewed':
      case 'scheduled':
        return StatusColors.info;
      case 'closed':
      case 'cancelled':
      case 'expired':
      case 'draft':
      case 'inactive':
      case 'low':
      default:
        return StatusColors.closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colorOverride ?? colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 46 : 26),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: isDark ? color : Color.lerp(color, Colors.black, 0.25)!,
        ),
      ),
    );
  }
}

/// Compact navy hero for sub-pages: back button + title + lime hairline.
/// Like DsHero, deliberately splash-navy in BOTH light and dark mode.
/// [bottom] hosts search fields / filter chips that should sit on navy.
class DsPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  final bool showBack;

  const DsPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.showBack = true,
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
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showBack)
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18, color: Colors.white),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                                color: Color(0xFF8FA3C8),
                              ),
                            ),
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
                          const SizedBox(height: 6),
                          const DsLimeLine(),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: bottom!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 13px w700 section heading with optional accent action.
class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  const DsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 10),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color:
                    isDark ? Brand.darkTextPrimary : const Color(0xFF0F2557),
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Friendly empty state: slate squircle + title + optional subtitle/CTA.
class DsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const DsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIconSquircle(
              icon: icon,
              color: isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8),
              size: 56,
              radius: 16,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? Brand.darkTextPrimary : const Color(0xFF0F2557),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : const Color(0xFF64748B),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Shared form-field decoration so form screens swap `decoration:` only.
class DsInputs {
  DsInputs._();

  static InputDecoration decoration(
    BuildContext context, {
    String? label,
    String? hint,
    IconData? icon,
    Widget? suffix,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Brand.darkBorder : const Color(0xFFE4E9F2);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon,
              size: 19,
              color: isDark ? Brand.darkIconActive : Brand.royalBlue),
      suffixIcon: suffix,
      filled: true,
      fillColor: isDark ? Brand.darkCardElevated : Brand.cardLight,
      isDense: true,
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: isDark ? Brand.darkTextSecondary : const Color(0xFF64748B),
      ),
      hintStyle: TextStyle(
        fontSize: 12.5,
        color: isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: StatusColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: StatusColors.danger, width: 1.5),
      ),
    );
  }
}
