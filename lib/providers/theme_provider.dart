// lib/providers/theme_provider.dart

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/brand_colors.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'isDarkMode';
  static const String _styleKey = 'dark_style';

  bool _isDarkMode = false;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isDarkMode => _isDarkMode;
  bool get isLoaded => _isLoaded;

  /// Which of the three dark looks is active (Navy Glow / Workshop / Fusion).
  DarkStyle get darkStyle => Brand.darkStyle;

  static String styleName(DarkStyle s) => switch (s) {
        DarkStyle.navy => 'Navy Glow',
        DarkStyle.workshop => 'Workshop',
        DarkStyle.fusion => 'Fusion',
      };

  /// Pick a dark look. Also switches the app into dark mode so the choice
  /// is visible immediately.
  Future<void> setDarkStyle(DarkStyle style) async {
    await _ensureLoaded();
    Brand.setDarkStyle(style);
    _isDarkMode = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_styleKey, style.name);
      await prefs.setBool(_themeKey, true);
    } catch (e) {
      debugPrint('⚠️ Dark style save failed: $e');
    }
  }

  ThemeProvider() {
    // Don't load immediately - defer until first access or explicit call
    // This saves ~30-50ms on app startup
    _ensureLoaded();
  }

  /// Ensure theme is loaded. Call this explicitly if needed, or it auto-loads on first access.
  Future<void> _ensureLoaded() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      await _loadThemePreference();
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themeKey) ?? false;
      final styleName = prefs.getString(_styleKey);
      final style = DarkStyle.values
          .where((s) => s.name == styleName)
          .firstOrNull;
      if (style != null) Brand.setDarkStyle(style);
    } catch (e) {
      _isDarkMode = false;
      debugPrint('⚠️ Theme preference load failed: $e');
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await _ensureLoaded();
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode);
    } catch (e) {
      debugPrint('⚠️ Theme preference save failed: $e');
    }
  }

  Future<void> setDarkMode(bool value) async {
    await _ensureLoaded();
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode);
    } catch (e) {
      debugPrint('⚠️ Theme preference save failed: $e');
    }
  }

  // ─── DS TYPOGRAPHY HELPERS ────────────────────────────────
  static TextTheme _montserratLight() =>
      GoogleFonts.montserratTextTheme(ThemeData.light().textTheme);

  static TextTheme _montserratDark() =>
      GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme);

  // ─── SHARED MODERN POLISH (both themes) ───────────────────
  // Fade-through page transitions + sparkle ink make navigation and taps
  // feel current on every screen without touching individual pages.
  static final PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: const FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
    },
  );

  // Note: no global showDragHandle — most sheets already draw their own.
  static const BottomSheetThemeData _bottomSheetLight = BottomSheetThemeData(
    backgroundColor: Brand.cardLight,
    surfaceTintColor: Colors.transparent,
    modalBackgroundColor: Brand.cardLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
  );

  static BottomSheetThemeData get _bottomSheetDark => BottomSheetThemeData(
        backgroundColor: Brand.darkCard,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Brand.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      );

  // ─── LIGHT THEME ──────────────────────────────────────────
  ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: Brand.royalBlue,
        scaffoldBackgroundColor: Brand.scaffoldLight,
        fontFamily: GoogleFonts.montserrat().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Brand.royalBlue,
          primary: Brand.royalBlue,
          secondary: Brand.lightGreen,
          surface: Brand.cardLight,
          brightness: Brightness.light,
        ),
        textTheme: _montserratLight(),
        primaryTextTheme: _montserratLight(),
        pageTransitionsTheme: _pageTransitions,
        splashFactory: InkSparkle.splashFactory,
        bottomSheetTheme: _bottomSheetLight,
        // ── Dialogs — rounded, no M3 surface tint ──
        dialogTheme: DialogThemeData(
          backgroundColor: Brand.cardLight,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: GoogleFonts.montserrat(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Brand.textPrimaryLight,
          ),
        ),
        // ── FAB ──
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Brand.royalBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        // ── Progress indicators ──
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Brand.royalBlue,
          linearTrackColor: Brand.royalBlueSurface,
          circularTrackColor: Colors.transparent,
        ),
        // ── ListTile ──
        listTileTheme: ListTileThemeData(
          iconColor: Brand.textSecondaryLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // ── AppBar — clean white, no border ──
        appBarTheme: AppBarTheme(
          backgroundColor: Brand.cardLight,
          foregroundColor: Brand.royalBlueDark,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: true,
          titleTextStyle: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Brand.royalBlueDark,
            letterSpacing: -0.3,
          ),
          iconTheme: const IconThemeData(color: Brand.royalBlueDark),
        ),
        // ── Cards — clean white, soft shadow, no border ──
        cardTheme: CardThemeData(
          color: Brand.cardLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          shadowColor: Colors.black.withAlpha(20),
        ),
        // ── Elevated Button ──
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Brand.royalBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        // ── Outlined Button ──
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.royalBlue,
            side: const BorderSide(color: Brand.borderLight, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // ── Text Button ──
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Brand.royalBlue,
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // ── Input ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Brand.cardLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Brand.borderLight, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Brand.borderLight, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Brand.royalBlue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          hintStyle: GoogleFonts.montserrat(
            fontSize: 14,
            color: Brand.subtleLight,
          ),
          labelStyle: GoogleFonts.montserrat(
            fontSize: 14,
            color: Brand.subtleLight,
          ),
        ),
        // ── Chip ──
        chipTheme: ChipThemeData(
          backgroundColor: Brand.royalBlueSurface,
          labelStyle: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Brand.royalBlue,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        // ── Divider ──
        dividerTheme: const DividerThemeData(
          color: Brand.borderLight,
          thickness: 1,
          space: 1,
        ),
        // ── SnackBar ──
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Brand.royalBlueDark,
          contentTextStyle: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  // ─── DARK THEME (variant-aware: Navy Glow / Workshop / Fusion) ──
  ThemeData get darkTheme {
    final p = Brand.darkPalette;
    return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: p.primary,
        scaffoldBackgroundColor: p.bg,
        fontFamily: GoogleFonts.montserrat().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Brand.royalBlue,
          primary: p.primary,
          onPrimary: p.onPrimary,
          secondary: p.secondary,
          surface: p.card,
          brightness: Brightness.dark,
        ),
        textTheme: _montserratDark(),
        primaryTextTheme: _montserratDark(),
        pageTransitionsTheme: _pageTransitions,
        splashFactory: InkSparkle.splashFactory,
        bottomSheetTheme: _bottomSheetDark,
        // ── Dialogs — rounded, no M3 surface tint ──
        dialogTheme: DialogThemeData(
          backgroundColor: Brand.darkCard,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: GoogleFonts.montserrat(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Brand.darkTextPrimary,
          ),
        ),
        // ── FAB ──
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        // ── Progress indicators ──
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p.iconActive,
          linearTrackColor: Brand.darkBorder,
          circularTrackColor: Colors.transparent,
        ),
        // ── ListTile ──
        listTileTheme: ListTileThemeData(
          iconColor: Brand.darkTextSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // ── AppBar ──
        appBarTheme: AppBarTheme(
          backgroundColor: Brand.darkCard,
          foregroundColor: Brand.darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: true,
          titleTextStyle: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Brand.darkTextPrimary,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Brand.darkTextPrimary),
        ),
        // ── Cards ──
        cardTheme: CardThemeData(
          color: Brand.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Brand.darkBorder, width: 1),
          ),
        ),
        // ── Elevated Button ──
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        // ── Outlined Button ──
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.darkIconActive,
            side: BorderSide(color: Brand.darkBorderLight, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // ── Text Button ──
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Brand.darkIconActive,
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // ── Input ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Brand.darkCardElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Brand.darkBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Brand.darkBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: Brand.darkIconActive, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5),
          ),
          hintStyle: GoogleFonts.montserrat(
            fontSize: 14,
            color: Brand.darkTextTertiary,
          ),
          labelStyle: GoogleFonts.montserrat(
            fontSize: 14,
            color: Brand.darkTextTertiary,
          ),
        ),
        // ── Chip ──
        chipTheme: ChipThemeData(
          backgroundColor: Brand.royalBlue.withAlpha(40),
          labelStyle: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Brand.darkIconActive,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        // ── Divider ──
        dividerTheme: DividerThemeData(
          color: Brand.darkBorder,
          thickness: 1,
          space: 1,
        ),
        // ── SnackBar ──
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Brand.darkCardElevated,
          contentTextStyle: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Brand.darkTextPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }
}
