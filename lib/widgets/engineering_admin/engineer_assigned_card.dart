// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/engineering_admin/engineer_assigned_card.dart
// Engineer Assigned rich card widget — rendered in chat for
// message_type = 'engineer_assigned'. Used by all 3 chat screens
// (EA chat, customer chat, engineer chat).
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';

class EngineerAssignedCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final bool isDark;

  // Optional: show a reassign button (EA chat only)
  final VoidCallback? onReassign;

  const EngineerAssignedCard({
    super.key,
    required this.metadata,
    required this.isDark,
    this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final engineerName = metadata['engineer_name'] as String? ?? 'Engineer';
    final profilePhoto = metadata['profile_photo'] as String?;
    final designation = metadata['designation'] as String? ?? 'Field Engineer';
    final avgRating = (metadata['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final totalJobs = (metadata['total_jobs'] as num?)?.toInt() ?? 0;
    final zone = metadata['zone'] as String? ?? '';
    final assignedAt = metadata['assigned_at'] as String?;
    final skills = (metadata['skills'] as List<dynamic>?)
            ?.map((s) => s.toString())
            .toList() ??
        [];
    final assignedByName = metadata['assigned_by_name'] as String? ?? '';

    final cardBg = Brand.surface(isDark);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary =
        isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    final successColor = const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: successColor.withAlpha(isDark ? 25 : 20),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(
                  color: successColor.withAlpha(isDark ? 50 : 40),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: successColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'YOUR ENGINEER HAS BEEN ASSIGNED',
                  style: TextStyle(
                    color: successColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),

          // ── Engineer info ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                _EngineerAvatar(
                  photoUrl: profilePhoto,
                  name: engineerName,
                  isDark: isDark,
                ),
                const SizedBox(width: 14),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engineerName,
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        designation,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFF59E0B), size: 16),
                          const SizedBox(width: 3),
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '  ($totalJobs jobs completed)',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Skills ──────────────────────────────────────────
          if (skills.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Text(
                'Certified in:',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: skills
                    .map((skill) => _SkillChip(skill: skill, isDark: isDark))
                    .toList(),
              ),
            ),
          ],

          // ── Zone + assigned time ─────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded,
                    size: 14, color: textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Zone: $zone',
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
                const SizedBox(width: 16),
                Icon(Icons.schedule_rounded,
                    size: 14, color: textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Assigned: ${_formatAssignedAt(assignedAt)}',
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),

          if (assignedByName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Text(
                'by $assignedByName',
                style: TextStyle(color: textSecondary, fontSize: 11),
              ),
            ),

          // ── Footer message ───────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkCardElevated
                  : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'The engineer will contact you shortly.\nYou may continue chatting here.',
              style: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),

          // ── Reassign button (EA only) ────────────────────────
          if (onReassign != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: OutlinedButton.icon(
                onPressed: onReassign,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Reassign Engineer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.warning,
                  side: BorderSide(color: AdminColors.warning.withAlpha(100)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatAssignedAt(String? isoString) {
    if (isoString == null) return 'Recently';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;
      final timeStr =
          '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${dt.minute.toString().padLeft(2, '0')} '
          '${dt.hour >= 12 ? 'PM' : 'AM'}';
      return isToday ? 'Today, $timeStr' : timeStr;
    } catch (_) {
      return 'Recently';
    }
  }
}

// ── Avatar ──────────────────────────────────────────────────────────────────

class _EngineerAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final bool isDark;

  const _EngineerAvatar({
    required this.photoUrl,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join()
        : '?';

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF10B981).withAlpha(100),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: 56,
                height: 56,
                placeholder: (_, __) => _Placeholder(
                  initials: initials,
                  isDark: isDark,
                ),
                errorWidget: (_, __, ___) => _Placeholder(
                  initials: initials,
                  isDark: isDark,
                ),
              )
            : _Placeholder(initials: initials, isDark: isDark),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String initials;
  final bool isDark;

  const _Placeholder({required this.initials, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Brand.royalBlue,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

// ── Skill chip ───────────────────────────────────────────────────────────────

class _SkillChip extends StatelessWidget {
  final String skill;
  final bool isDark;

  const _SkillChip({required this.skill, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Brand.royalBlue.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Brand.royalBlue.withAlpha(isDark ? 60 : 40),
        ),
      ),
      child: Text(
        skill,
        style: TextStyle(
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
