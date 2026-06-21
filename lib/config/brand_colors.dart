import 'package:flutter/material.dart';

/// The three selectable dark looks.
///  - navy:     "Navy Glow" — deep radial-navy family from the splash screen
///  - workshop: "Workshop" — warm ink canvas, paper-white text, lime active
///  - fusion:   "Fusion" — navy depth with Workshop's outlined structure
enum DarkStyle { navy, workshop, fusion }

/// The two selectable STRUCTURAL designs (independent of light/dark).
///  - navyGlow: radial splash-navy heroes, soft-bordered cards, rounded pills
///  - workshop: paper canvas, ink-outlined bento cards, perforated tickets,
///              tilted "sticker" status chips, lime spark accents
///
/// DS components branch on [Brand.design] so a single setting flips the entire
/// app between the two looks without duplicating any screen code.
enum AppDesign { navyGlow, workshop }

/// Which hero color family a screen uses (the Navy Glow header gradient).
///  - navy:    splash-navy (customer / admin / auth)
///  - emerald: emerald → black (engineering-admin)
///  - cyan:    cyan → dark (field engineer)
///  - violet:  violet → dark (marketing admin)
enum HeroAccent { navy, emerald, cyan, violet }

/// One hero color family: the radial gradient + the frosted "act now" card
/// colors that sit on top of it.
class HeroPalette {
  final List<Color> gradient; // glow → core → edge
  final Color frostedCard;
  final Color frostedBorder;
  final Color label; // muted label text on the hero
  const HeroPalette(
    this.gradient,
    this.frostedCard,
    this.frostedBorder,
    this.label,
  );
}

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

  // ─── Emerald → black hero family (Engineering-Admin) ──────────────
  static const Color emeraldHeroEdge = Color(0xFF04140E); // near-black
  static const Color emeraldHeroCore = Color(0xFF0A4030);
  static const Color emeraldHeroGlow = Color(0xFF0F7B54);
  static const Color emeraldBright = Color(0xFF34D399); // mint spark

  // ─── Cyan → dark hero family (Field Engineer) ───────────────────
  static const Color cyanHeroEdge = Color(0xFF062A3A);
  static const Color cyanHeroCore = Color(0xFF0E5A72);
  static const Color cyanHeroGlow = Color(0xFF0891B2);
  static const Color cyanBright = Color(0xFF22D3EE); // sky spark

  // ─── Violet → dark hero family (Marketing Admin) ────────────────
  static const Color violetHeroEdge = Color(0xFF1E0650);
  static const Color violetHeroCore = Color(0xFF3B0F8C);
  static const Color violetHeroGlow = Color(0xFF6D28D9);
  static const Color violetBright = Color(0xFFA78BFA); // lavender spark

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

  // ═══════════════════════════════════════════════════════════════
  // STRUCTURAL DESIGN (Navy Glow vs Workshop) — the master look switch
  // ═══════════════════════════════════════════════════════════════

  static AppDesign _design = AppDesign.navyGlow;
  static AppDesign get design => _design;
  static bool get isWorkshop => _design == AppDesign.workshop;

  /// Swap the structural design. DS components read [design] on rebuild.
  static void setDesign(AppDesign d) => _design = d;

  // ── Hero accent families ──────────────────────────────────────
  static const HeroPalette navyHero = HeroPalette(
    [splashNavyGlow, splashNavyCore, splashNavyEdge],
    Color(0xD916294F),
    Color(0xFF2A3F6E),
    Color(0xFF8FA3C8),
  );
  static const HeroPalette emeraldHero = HeroPalette(
    [emeraldHeroGlow, emeraldHeroCore, emeraldHeroEdge],
    Color(0xD90C3A2A),
    Color(0xFF1E5C44),
    Color(0xFF8FC8B0),
  );
  static const HeroPalette cyanHero = HeroPalette(
    [cyanHeroGlow, cyanHeroCore, cyanHeroEdge],
    Color(0xD90B3A4D),
    Color(0xFF0E5A72),
    Color(0xFF7FD4E8),
  );
  static const HeroPalette violetHero = HeroPalette(
    [violetHeroGlow, violetHeroCore, violetHeroEdge],
    Color(0xD92A0A6B),
    Color(0xFF4A1A9E),
    Color(0xFFBBA4F0),
  );

  static HeroPalette heroFor(HeroAccent a) => switch (a) {
        HeroAccent.emerald => emeraldHero,
        HeroAccent.cyan => cyanHero,
        HeroAccent.violet => violetHero,
        HeroAccent.navy => navyHero,
      };

  // ── Workshop palette ──────────────────────────────────────────
  // Light: warm paper canvas + confident ink outlines (readable outdoors).
  static const Color workshopPaper = Color(0xFFF7F5F0);
  static const Color workshopInk = Color(0xFF1A1D29);
  static const Color workshopInkSoft = Color(0xFF6B6E7B);
  static const Color workshopHairline = Color(0xFFC9C5BA);
  // Dark: ink canvas, paper-white text — lime spark pops harder.
  static const Color workshopCanvasDark = Color(0xFF14161F);
  static const Color workshopCardDark = Color(0xFF1C1F2B);
  static const Color workshopInkDark = Color(0xFFF2EFE6);

  /// Page/scaffold background for the active design + brightness.
  static Color canvas(bool isDark) {
    if (isWorkshop) return isDark ? workshopCanvasDark : workshopPaper;
    return isDark ? darkBg : scaffoldLight;
  }

  /// Card surface for the active design + brightness.
  static Color surface(bool isDark) {
    if (isWorkshop) return isDark ? workshopCardDark : Colors.white;
    return isDark ? darkCard : cardLight;
  }

  /// Card border. Workshop = strong ink outline; Navy Glow = soft hairline.
  static Color cardBorder(bool isDark) {
    if (isWorkshop) {
      return isDark ? const Color(0xFF3A3E4F) : workshopInk;
    }
    return isDark ? darkBorder : const Color(0xFFE4E9F2);
  }

  /// Card border width — Workshop draws a bold 1.5px ink outline.
  static double get cardBorderWidth => isWorkshop ? 1.5 : 1.0;

  /// Card corner radius — Workshop is slightly tighter / more "panel".
  static double get cardRadius => isWorkshop ? 14 : 16;

  /// Scale any radius for the active design. Workshop pulls radii ~35% tighter;
  /// NavyGlow returns the value unchanged. Use for Container(BoxDecoration(...))
  /// cards that don't inherit from ThemeData.
  ///   `BorderRadius.circular(Brand.r(16))`
  static double r(double navyGlow) =>
      isWorkshop ? (navyGlow * 0.65).roundToDouble() : navyGlow;

  /// Primary text for the active design + brightness.
  static Color ink(bool isDark) {
    if (isWorkshop) return isDark ? workshopInkDark : workshopInk;
    return isDark ? darkTextPrimary : const Color(0xFF0F2557);
  }

  /// Secondary/muted text.
  static Color inkSoft(bool isDark) {
    if (isWorkshop) {
      return isDark ? const Color(0xFFA4A7B5) : workshopInkSoft;
    }
    return isDark ? darkTextSecondary : const Color(0xFF64748B);
  }

  // ─── Dark Theme (resolved through the active palette) ───
  static Color get darkBg => _dark.bg;
  static Color get darkCard => _dark.card;
  static Color get darkCardElevated => _dark.cardElevated;
  static Color get darkBorder => _dark.border;
  static Color get darkBorderLight => _dark.borderLight;
  static const Color darkCardHighlight = Color(0xFF22272E); // engineer dark card tint

  // ─── Light Theme (premium clean whites) ─────────
  static const Color scaffoldLight = Color(0xFFF8FAFC);
  static const Color cardLight = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderMedium = Color(0xFFCBD5E1); // slate-200
  static const Color slateLight = Color(0xFFF1F5F9);   // slate-100

  // ─── Text ───────────────────────────────────────
  static const Color subtleLight = Color(0xFF94A3B8);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textSlate = Color(0xFF475569);     // slate-600
  static const Color textGray = Color(0xFF374151);      // gray-700
  static Color get darkTextPrimary => _dark.textPrimary;
  static Color get darkTextSecondary => _dark.textSecondary;
  static Color get darkTextTertiary => _dark.textTertiary;
  static Color get darkIconActive => _dark.iconActive;

  // ─── Dark Surface Shades ───────────────────────
  // These represent the range of navy/dark-mode card backgrounds used across
  // engineer and admin screens. New screens should use Brand.canvas(isDark) /
  // Brand.surface(isDark) instead; these constants are for existing inline usages.
  static const Color darkSurface = Color(0xFF1E293B);       // slate-800 — dark card bg
  static const Color darkNavy = Color(0xFF1A1F36);          // deep navy panel
  static const Color darkDeep = Color(0xFF1A1A2E);          // darkest dark-mode bg
  static const Color navyMid = Color(0xFF2A3F6E);           // medium navy accent

  // ─── Misc brand colours ────────────────────────
  static const Color whatsappGreen = Color(0xFF25D366);  // WhatsApp CTA
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

  // Extended status shades (used in installation, job-record, completion flows)
  static const Color resolved = Color(0xFF10B981); // emerald — completed/resolved
  static const Color teal = Color(0xFF14B8A6); // teal — service/catalog accent
  static const Color indigo = Color(0xFF6366F1); // indigo — analytics/kb accent
  static const Color pink = Color(0xFFEC4899); // pink — banners/marketing accent
  static const Color gray = Color(0xFF6B7280); // neutral gray — default/unknown states
  static const Color subtle = Color(0xFF94A3B8); // light slate — hint/tertiary text

  // Soft / light variants (notification cards, loyalty tier cards, inline badges)
  static const Color softRed = Color(0xFFFF6B6B);      // coral-red — delete/error emphasis
  static const Color coral = Color(0xFFFF4757);         // bright red-coral — CTA danger
  static const Color warningLight = Color(0xFFFFB74D);  // amber-300 — soft warning chip
  static const Color materialOrange = Color(0xFFFF9800); // material orange — timeline
  static const Color lavender = Color(0xFFCE93D8);      // light purple — loyalty/tier
  static const Color deepPurple = Color(0xFF6A1B9A);    // deep purple — premium tier
  static const Color materialGreen = Color(0xFF4CAF50); // material green — success alt
  static const Color materialBlue = Color(0xFF2196F3);  // material blue — info alt
  static const Color skyBlue = Color(0xFF0EA5E9);       // sky-blue (= AdminColors.eaAccent)
  static const Color mutedGray = Color(0xFF9E9E9E);     // muted gray — disabled states
}

/// L3: Tier colours. Loyalty tiers (customer portal + marketing portal) were
/// re-declaring these hex codes inline. One canonical location prevents drift.
class TierColors {
  TierColors._();

  static const Color bronze = Color(0xFFCD7F32);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color gold = Color(0xFFFFD700);
  static const Color platinum = Color(0xFF00B4D8); // cyan-teal

  static Color forTier(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'platinum': return platinum;
      case 'gold': return gold;
      case 'silver': return silver;
      default: return bronze;
    }
  }
}

/// L4: Chart / analytics series colours. Data-vis screens were declaring
/// inline Color(0xFF...) per series. Named palette prevents series-colour
/// drift across the analytics dashboard, KPI graphs, and marketing pages.
class ChartColors {
  ChartColors._();

  static const Color blue = Color(0xFF3B82F6);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color amber = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
  static const Color teal = Color(0xFF14B8A6);
  static const Color pink = Color(0xFFEC4899);
  static const Color orange = Color(0xFFF97316);
  static const Color indigo = Color(0xFF6366F1);
  static const Color emerald = Color(0xFF10B981);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color gray = Color(0xFF6B7280);

  /// Ordered series palette — use index to pick a colour for the Nth data series.
  static const List<Color> series = [blue, purple, amber, red, teal, pink, orange, indigo];
}
