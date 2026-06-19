// lib/providers/theme_provider.dart

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/brand_colors.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'isDarkMode';
  static const String _styleKey = 'dark_style';
  static const String _designKey = 'app_design';

  bool _isDarkMode = false;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isDarkMode => _isDarkMode;
  bool get isLoaded => _isLoaded;

  /// Which of the three dark looks is active (Navy Glow / Workshop / Fusion).
  DarkStyle get darkStyle => Brand.darkStyle;

  /// The active STRUCTURAL design (Navy Glow vs Workshop) — flips every
  /// DS-based screen between the two looks.
  AppDesign get design => Brand.design;

  static String designName(AppDesign d) => switch (d) {
        AppDesign.navyGlow => 'Navy Glow',
        AppDesign.workshop => 'Workshop',
      };

  /// Pick the structural design. Persists and rebuilds the whole tree.
  Future<void> setDesign(AppDesign d) async {
    await _ensureLoaded();
    Brand.setDesign(d);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_designKey, d.name);
    } catch (e) {
      debugPrint('⚠️ App design save failed: $e');
    }
  }

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

  static double get _r => Brand.isWorkshop ? 10.0 : 28.0;

  static BottomSheetThemeData get _bottomSheetLight => BottomSheetThemeData(
        backgroundColor: Brand.surface(false),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Brand.surface(false),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_r)),
          side: Brand.isWorkshop
              ? BorderSide(
                  color: Brand.cardBorder(false), width: Brand.cardBorderWidth)
              : BorderSide.none,
        ),
      );

  static BottomSheetThemeData get _bottomSheetDark => BottomSheetThemeData(
        backgroundColor: Brand.surface(true),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Brand.surface(true),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_r)),
          side: Brand.isWorkshop
              ? BorderSide(
                  color: Brand.cardBorder(true), width: Brand.cardBorderWidth)
              : BorderSide.none,
        ),
      );

  // ─── Shared Workshop-aware radii ──────────────────────────
  static double get _cardR => Brand.cardRadius;
  static double get _btnR => Brand.isWorkshop ? 8.0 : 14.0;
  static double get _inputR => Brand.isWorkshop ? 8.0 : 14.0;
  static double get _dialogR => Brand.isWorkshop ? 10.0 : 20.0;
  static double get _fabR => Brand.isWorkshop ? 10.0 : 16.0;
  static double get _chipR => Brand.isWorkshop ? 6.0 : 10.0;
  static double get _snackR => Brand.isWorkshop ? 6.0 : 12.0;

  // ─── LIGHT THEME ──────────────────────────────────────────
  ThemeData get lightTheme {
    final bg = Brand.canvas(false);
    final card = Brand.surface(false);
    final border = Brand.cardBorder(false);
    final bw = Brand.cardBorderWidth;
    final textP = Brand.ink(false);
    final textS = Brand.inkSoft(false);
    final ws = Brand.isWorkshop;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: Brand.royalBlue,
      scaffoldBackgroundColor: bg,
      fontFamily: GoogleFonts.montserrat().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.royalBlue,
        primary: Brand.royalBlue,
        secondary: Brand.lightGreen,
        surface: card,
        brightness: Brightness.light,
      ),
      textTheme: _montserratLight(),
      primaryTextTheme: _montserratLight(),
      pageTransitionsTheme: _pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      bottomSheetTheme: _bottomSheetLight,
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_dialogR),
          side: ws ? BorderSide(color: border, width: bw) : BorderSide.none,
        ),
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textP,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Brand.royalBlue,
        foregroundColor: Colors.white,
        elevation: ws ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_fabR),
          side: ws ? BorderSide(color: border, width: bw) : BorderSide.none,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Brand.royalBlue,
        linearTrackColor: Brand.royalBlueSurface,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textS,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ws ? 8 : 12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: textP,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: !ws,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: ws ? 20 : 18,
          fontWeight: ws ? FontWeight.w800 : FontWeight.w600,
          color: textP,
          letterSpacing: ws ? -0.5 : -0.3,
        ),
        iconTheme: IconThemeData(color: textP),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardR),
          side: ws ? BorderSide(color: border, width: bw) : BorderSide.none,
        ),
        shadowColor: ws ? Colors.transparent : Colors.black.withAlpha(20),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.royalBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnR),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.royalBlue,
          side: BorderSide(color: border, width: bw),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnR),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.royalBlue,
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: BorderSide(color: border, width: bw),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: BorderSide(color: border, width: bw),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: const BorderSide(color: Brand.royalBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        hintStyle: GoogleFonts.montserrat(
          fontSize: 14,
          color: textS,
        ),
        labelStyle: GoogleFonts.montserrat(
          fontSize: 14,
          color: textS,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            ws ? Brand.workshopInk.withAlpha(15) : Brand.royalBlueSurface,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ws ? Brand.workshopInk : Brand.royalBlue,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_chipR),
          side: ws ? BorderSide(color: border, width: 1) : BorderSide.none,
        ),
        side: ws ? BorderSide(color: border, width: 1) : BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ws ? Brand.workshopInk : Brand.royalBlueDark,
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_snackR),
        ),
      ),
    );
  }

  // ─── DARK THEME (variant-aware: Navy Glow / Workshop / Fusion) ──
  ThemeData get darkTheme {
    final p = Brand.darkPalette;
    final card = Brand.surface(true);
    final border = Brand.cardBorder(true);
    final bw = Brand.cardBorderWidth;
    final textP = Brand.ink(true);
    final textS = Brand.inkSoft(true);
    final ws = Brand.isWorkshop;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: p.primary,
      scaffoldBackgroundColor: Brand.canvas(true),
      fontFamily: GoogleFonts.montserrat().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.royalBlue,
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.secondary,
        surface: card,
        brightness: Brightness.dark,
      ),
      textTheme: _montserratDark(),
      primaryTextTheme: _montserratDark(),
      pageTransitionsTheme: _pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      bottomSheetTheme: _bottomSheetDark,
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_dialogR),
          side: ws ? BorderSide(color: border, width: bw) : BorderSide.none,
        ),
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textP,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: ws ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_fabR),
          side: ws ? BorderSide(color: border, width: bw) : BorderSide.none,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.iconActive,
        linearTrackColor: Brand.darkBorder,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textS,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ws ? 8 : 12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: textP,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: !ws,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: ws ? 20 : 18,
          fontWeight: ws ? FontWeight.w800 : FontWeight.w600,
          color: textP,
          letterSpacing: ws ? -0.5 : -0.3,
        ),
        iconTheme: IconThemeData(color: textP),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardR),
          side: BorderSide(color: border, width: bw),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnR),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.darkIconActive,
          side: BorderSide(color: border, width: bw),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnR),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.darkIconActive,
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Brand.darkCardElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: BorderSide(color: border, width: bw),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: BorderSide(color: border, width: bw),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: BorderSide(color: Brand.darkIconActive, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
          borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputR),
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
      chipTheme: ChipThemeData(
        backgroundColor: Brand.royalBlue.withAlpha(40),
        labelStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Brand.darkIconActive,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_chipR),
          side: ws ? BorderSide(color: border, width: 1) : BorderSide.none,
        ),
        side: ws ? BorderSide(color: border, width: 1) : BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Brand.darkCardElevated,
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textP,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_snackR),
        ),
      ),
    );
  }
}
