// lib/config/app_theme.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { outlinedDark, softLight }

class AppThemeData {
  final String name;
  final Color background;
  final Color cardBackground;
  final Color accent;
  final Color iconBackground;
  final Color iconColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderColor;
  final Color navBackground;
  final Color inputBackground;
  final Brightness brightness;

  const AppThemeData({
    required this.name,
    required this.background,
    required this.cardBackground,
    required this.accent,
    required this.iconBackground,
    required this.iconColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderColor,
    required this.navBackground,
    required this.inputBackground,
    required this.brightness,
  });
}

class AppTheme extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  bool _isLoaded = false;

  AppThemeMode _currentMode = AppThemeMode.softLight;
  AppThemeMode get currentMode => _currentMode;
  bool get isLoaded => _isLoaded;

  static final Map<AppThemeMode, AppThemeData> _themes = {
    AppThemeMode.outlinedDark: const AppThemeData(
      name: 'Dark',
      background: Color(0xFF0D1117),
      cardBackground: Color(0xFF161B22),
      accent: Color(0xFF58A6FF),
      iconBackground: Color(0x1A58A6FF),
      iconColor: Color(0xFF58A6FF),
      textPrimary: Color(0xFFE6EDF3),
      textSecondary: Color(0xFF8B949E),
      borderColor: Color(0xFF21262D),
      navBackground: Color(0xFF161B22),
      inputBackground: Color(0xFF1C2129),
      brightness: Brightness.dark,
    ),
    AppThemeMode.softLight: const AppThemeData(
      name: 'Light',
      background: Color(0xFFF4F6FA),
      cardBackground: Color(0xFFFFFFFF),
      accent: Color(0xFF1A3C8E),
      iconBackground: Color(0x141A3C8E),
      iconColor: Color(0xFF1A3C8E),
      textPrimary: Color(0xFF0F2557),
      textSecondary: Color(0xFF94A3B8),
      borderColor: Color(0xFFE2E8F0),
      navBackground: Color(0xFFFFFFFF),
      inputBackground: Color(0xFFF1F5F9),
      brightness: Brightness.light,
    ),
  };

  AppThemeData get theme => _themes[_currentMode]!;

  bool get isDark => _currentMode == AppThemeMode.outlinedDark;

  AppTheme() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_themeKey);
      if (index != null) {
        if (index >= AppThemeMode.values.length) {
          _currentMode = AppThemeMode.outlinedDark;
          await prefs.setInt(_themeKey, _currentMode.index);
        } else {
          _currentMode = AppThemeMode.values[index];
        }
      } else {
        _currentMode = AppThemeMode.softLight;
      }
    } catch (e) {
      _currentMode = AppThemeMode.softLight;
      debugPrint('⚠️ Theme load failed: $e');
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode mode) async {
    if (_currentMode == mode) return; // Avoid unnecessary rebuilds
    _currentMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, mode.index);
    } catch (e) {
      debugPrint('⚠️ Theme save failed: $e');
    }
  }

  Future<void> cycleTheme() async {
    final nextIndex = (_currentMode.index + 1) % AppThemeMode.values.length;
    await setTheme(AppThemeMode.values[nextIndex]);
  }

  static List<AppThemeMode> get allModes => AppThemeMode.values;
  static String modeName(AppThemeMode mode) => _themes[mode]!.name;
}
