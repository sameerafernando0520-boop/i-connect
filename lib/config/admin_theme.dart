// lib/config/admin_theme.dart

import 'package:flutter/material.dart';
import 'brand_colors.dart';

// ═════════════════════════════════════════════════════════════
// ADMIN COLORS
// ═════════════════════════════════════════════════════════════

class AdminColors {
  AdminColors._();

  // ── Primary (premium corporate blue) ────────────────────────
  static const Color primary = Color(0xFF1A56DB);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E3A5F);

  // ── Accent / Status ────────────────────────────────────────
  static const Color accent = Color(0xFF22C55E);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color internal = Color(0xFFF97316);

  // ── Light-only constants ───────────────────────────────────
  static const Color background = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textTertiaryLight = Color(0xFF94A3B8);
  static const Color borderLightColor = Color(0xFFE2E8F0);

  // ══════════════════════════════════════════════════════════
  // BACKWARD-COMPAT GETTERS
  // Old files use: AdminColors.surface (no parentheses)
  // These return light-only colors — safe for non-dark-mode pages
  // ══════════════════════════════════════════════════════════

  static Color get surface => surfaceLight;
  static Color get textSecondary => textSecondaryLight;
  static Color get textTertiary => textTertiaryLight;
  static Color get borderLight => borderLightColor;

  // ══════════════════════════════════════════════════════════
  // THEME-AWARE METHODS (auto dark/light)
  // New files use: AdminColors.card(context)
  // ══════════════════════════════════════════════════════════

  static bool _isDark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  // These route through the design-aware Brand helpers so the entire staff UI
  // (admin / marketing / engineering-admin, which all consume AdminColors)
  // flips between Navy Glow and Workshop with the design switch. In Navy Glow
  // mode the helpers return the previous values — zero visual change.

  /// Card / panel surface background
  static Color card(BuildContext ctx) => Brand.surface(_isDark(ctx));

  /// Elevated card (slightly lighter in dark)
  static Color cardElevated(BuildContext ctx) =>
      _isDark(ctx) ? Brand.darkCardElevated : surfaceLight;

  /// Scaffold / page background
  static Color bg(BuildContext ctx) => Brand.canvas(_isDark(ctx));

  /// Border / divider line
  static Color border(BuildContext ctx) => Brand.cardBorder(_isDark(ctx));

  /// Divider (alias for border)
  static Color divider(BuildContext ctx) => border(ctx);

  /// Primary text color
  static Color text(BuildContext ctx) => Brand.ink(_isDark(ctx));

  /// Secondary text color (theme-aware)
  static Color textSub(BuildContext ctx) => Brand.inkSoft(_isDark(ctx));

  /// Tertiary / hint text color (theme-aware)
  static Color textHint(BuildContext ctx) =>
      _isDark(ctx) ? Brand.darkTextTertiary : textTertiaryLight;

  // ── Aliases for some new pages ─────────────────────────────
  static Color scaffoldBg(BuildContext ctx) => bg(ctx);
  static Color surfaceElevated(BuildContext ctx) => cardElevated(ctx);
  static Color textPrimaryAdaptive(BuildContext ctx) => text(ctx);

  // ══════════════════════════════════════════════════════════
  // STATUS / PRIORITY / SALES STAGE COLORS
  // ══════════════════════════════════════════════════════════

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return info;
      case 'assigned':
        return const Color(0xFF8E24AA);
      case 'in_progress':
        return warning;
      case 'resolved':
        return accent;
      case 'closed':
        return const Color(0xFF607D8B);
      case 'escalated':
        return error;
      case 'active':
        return accent;
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'defaulted':
        return error;
      default:
        return Colors.grey;
    }
  }

  static Color priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'low':
        return accent;
      case 'medium':
        return warning;
      case 'high':
        return const Color(0xFFFF5722);
      case 'urgent':
        return error;
      default:
        return Colors.grey;
    }
  }

  static Color salesStageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'new':
        return info;
      case 'contacted':
        return const Color(0xFF8E24AA);
      case 'quoted':
        return warning;
      case 'negotiating':
        return const Color(0xFFFF8F00);
      case 'won':
        return accent;
      case 'lost':
        return error;
      default:
        return Colors.grey;
    }
  }
}

// ═════════════════════════════════════════════════════════════
// ADMIN DIMENSIONS
// ═════════════════════════════════════════════════════════════

class AdminDimens {
  AdminDimens._();

  static const double cardRadius = 18.0;
  static const double smallCardRadius = 12.0;
  static const double sheetRadius = 28.0;
  static const double avatarSize = 48.0;
  static const double iconBoxSize = 44.0;
  static const double smallIconBox = 36.0;
  static const double pagePadding = 20.0;
  static const double cardPadding = 16.0;
  static const double itemSpacing = 12.0;
}

// ═════════════════════════════════════════════════════════════
// ADMIN TEXT STYLES  (DS-aligned — Montserrat weights)
// ═════════════════════════════════════════════════════════════

class AdminStyles {
  AdminStyles._();

  // 20 / 600 — page titles (semi-bold, consistent across all screens)
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AdminColors.textPrimary,
    letterSpacing: -0.3,
  );

  // 18 / 600 — dashboard hero name / greeting name
  static const TextStyle heroTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AdminColors.primaryDark,
    letterSpacing: -0.3,
  );

  // 17 / 600 — section headings (Overview, Quick Actions, etc.)
  static const TextStyle sectionHeading = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AdminColors.textPrimary,
    letterSpacing: -0.2,
  );

  // 16 / 700 — sub-section titles
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AdminColors.textPrimary,
  );

  // 15 / 800 — card titles / person names
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AdminColors.primaryDark,
  );

  // 14 / 400 / lh 1.5 — body text
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AdminColors.textPrimary,
    height: 1.5,
  );

  // 13 / 400 — small body / input text
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AdminColors.textSecondaryLight,
  );

  // 12 / 500 — card subtitles / meta info
  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AdminColors.textSecondaryLight,
  );

  // 12 / 600 / uppercase / +0.5 — section labels (raised from 11 for legibility)
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AdminColors.textSecondaryLight,
    letterSpacing: 0.5,
  );

  // 28 / 700 / -0.5 — large stat numbers
  static const TextStyle bigNumber = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AdminColors.primaryDark,
    letterSpacing: -0.5,
  );

  // 22 / 900 / -0.3 — compact stat numbers (engineer cards, mini stats)
  static const TextStyle statNumber = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AdminColors.primaryDark,
    letterSpacing: -0.3,
  );

  // 11 / 800 / uppercase / +0.5 — status badges / tags (raised from 9)
  static const TextStyle tag = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // 11 / 600 — small tag / specialty chip (raised from 10)
  static const TextStyle tagSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );
}
