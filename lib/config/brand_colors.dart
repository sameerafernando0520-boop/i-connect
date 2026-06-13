import 'package:flutter/material.dart';

/// The three selectable dark looks.
///  - navy:     "Navy Glow" — deep radial-navy family from the splash screen
///  - workshop: "Workshop" — warm ink canvas, paper-white text, lime active
///  - fusion:   "Fusion" — navy depth with Workshop's outlined structure
enum DarkStyle { navy, workshop, fusion }

/// One dark palette. All `Brand.dark*` getters resolve through the active one.
class DarkPalette {
  final Color bg;
  final Color card;
  final Color cardElevated;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color iconActive;
  final Color primary;
  final Color onPrimary;
  final Color secondary;

  const DarkPalette({
    required this.bg,
    required this.card,
    required this.cardElevated,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.iconActive,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
  });
}

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

  // ─── Brand spark (lime from the splash / iFrontiers logo) ──
  static const Color lime = Color(0xFFABBD37);

  // ─── Splash navy family ─────────────────────────
  static const Color splashNavyEdge = Color(0xFF081A40);
  static const Color splashNavyCore = Color(0xFF102A63);
  static const Color splashNavyGlow = Color(0xFF15397A);

  // ─── Dark palettes (selectable) ─────────────────
  static const DarkPalette navyGlowPalette = DarkPalette(
    bg: Color(0xFF0A1834),
    card: Color(0xFF122754),
    cardElevated: Color(0xFF18305F),
    border: Color(0xFF27407A),
    borderLight: Color(0xFF33518F),
    textPrimary: Color(0xFFECF1FB),
    textSecondary: Color(0xFF93A7CC),
    textTertiary: Color(0xFF62759E),
    iconActive: Color(0xFF6C9BFF),
    primary: Color(0xFF3B82F6),
    onPrimary: Colors.white,
    secondary: lime,
  );

  static const DarkPalette workshopPalette = DarkPalette(
    bg: Color(0xFF14161F),
    card: Color(0xFF1C1F2B),
    cardElevated: Color(0xFF232737),
    border: Color(0xFF3A3E4F),
    borderLight: Color(0xFF4A4F63),
    textPrimary: Color(0xFFF2EFE6),
    textSecondary: Color(0xFFA4A7B5),
    textTertiary: Color(0xFF6E7180),
    iconActive: lime,
    primary: lime,
    onPrimary: Color(0xFF14161F),
    secondary: Color(0xFF6C9BFF),
  );

  static const DarkPalette fusionPalette = DarkPalette(
    bg: Color(0xFF0C1222),
    card: Color(0xFF151D33),
    cardElevated: Color(0xFF1B2440),
    border: Color(0xFF2C3552),
    borderLight: Color(0xFF3A4566),
    textPrimary: Color(0xFFEDF1F9),
    textSecondary: Color(0xFF98A4C0),
    textTertiary: Color(0xFF66708C),
    iconActive: Color(0xFF7FA8F5),
    primary: Color(0xFF5B8DEF),
    onPrimary: Colors.white,
    secondary: lime,
  );

  static DarkPalette _dark = navyGlowPalette;
  static DarkStyle _style = DarkStyle.navy;

  static DarkStyle get darkStyle => _style;
  static DarkPalette get darkPalette => _dark;

  static DarkPalette paletteFor(DarkStyle s) => switch (s) {
        DarkStyle.navy => navyGlowPalette,
        DarkStyle.workshop => workshopPalette,
        DarkStyle.fusion => fusionPalette,
      };

  /// Swap the active dark palette. Called by ThemeProvider; every widget
  /// reading `Brand.dark*` picks the new colors up on its next rebuild.
  static void setDarkStyle(DarkStyle s) {
    _style = s;
    _dark = paletteFor(s);
  }

  // ─── Dark Theme (resolved through the active palette) ───
  static Color get darkBg => _dark.bg;
  static Color get darkCard => _dark.card;
  static Color get darkCardElevated => _dark.cardElevated;
  static Color get darkBorder => _dark.border;
  static Color get darkBorderLight => _dark.borderLight;

  // ─── Light Theme (premium clean whites) ─────────
  static const Color scaffoldLight = Color(0xFFF8FAFC);
  static const Color cardLight = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0);

  // ─── Text ───────────────────────────────────────
  static const Color subtleLight = Color(0xFF94A3B8);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static Color get darkTextPrimary => _dark.textPrimary;
  static Color get darkTextSecondary => _dark.textSecondary;
  static Color get darkTextTertiary => _dark.textTertiary;
  static Color get darkIconActive => _dark.iconActive;
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
  static const Color success = Color(0xFF22C55E); // green — resolved/paid/accepted

  // Severity / banners
  static const Color warning = Color(0xFFF59E0B); // amber
  static const Color warningDark = Color(0xFFD97706); // amber-dark
  static const Color danger = Color(0xFFEF4444); // red
  static const Color info = Color(0xFF06B6D4); // cyan
}
