import 'package:flutter/material.dart';

class Brand {
  Brand._(); // prevent instantiation

  // ─── Royal Blue Family (premium corporate blue) ────────
  static const Color royalBlue = Color(0xFF1A56DB);
  static const Color royalBlueDark = Color(0xFF1E3A5F);
  static const Color royalBlueLight = Color(0xFF3B82F6);
  static const Color royalBlueSurface = Color(0xFFEFF6FF);
  static const Color royalBlueGlow = Color(0xFF60A5FA);

  // ─── Green Family ──────────────────────────────
  static const Color lightGreen = Color(0xFF22C55E);
  static const Color lightGreenDark = Color(0xFF16A34A);
  static const Color lightGreenBright = Color(0xFF4ADE80);
  static const Color lightGreenSurface = Color(0xFFF0FDF4);

  // ─── Dark Theme ─────────────────────────────────
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkCardElevated = Color(0xFF273548);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkBorderLight = Color(0xFF475569);

  // ─── Light Theme (premium clean whites) ─────────
  static const Color scaffoldLight = Color(0xFFF8FAFC);
  static const Color cardLight = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0);

  // ─── Text ───────────────────────────────────────
  static const Color subtleLight = Color(0xFF94A3B8);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);
  static const Color darkIconActive = Color(0xFF60A5FA);
}

/// L2: Canonical semantic/status palette.
///
/// Status-bound screens (tickets, inquiries, invoices) were re-declaring the
/// same hex codes inline. Keeping them here means a future brand re-skin is a
/// one-file change and prevents "orange is 0xFFFF9800 here but 0xFFF59E0B
/// three files over" drift.
class StatusColors {
  StatusColors._();

  // Ticket / inquiry lifecycle
  static const Color open = Color(0xFF3B82F6); // blue
  static const Color assigned = Color(0xFF8B5CF6); // purple
  static const Color inProgress = Color(0xFFF59E0B); // amber
  static const Color waiting = Color(0xFFF97316); // orange
  static const Color closed = Color(0xFF64748B); // slate

  // Severity / banners
  static const Color warning = Color(0xFFF59E0B); // amber
  static const Color warningDark = Color(0xFFD97706); // amber-dark
  static const Color danger = Color(0xFFEF4444); // red
  static const Color info = Color(0xFF06B6D4); // cyan
}
