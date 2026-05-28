import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

class LocaleProvider extends ChangeNotifier {
  // ── Per-user key prefix ──
  // Each user gets their own saved locale under 'app_locale_$userId'.
  // A logged-out/anonymous fallback uses 'app_locale_guest'.
  static const String _prefPrefix = 'app_locale_';
  static const String _guestSuffix = 'guest';
  static const Locale _fallback = Locale('en');

  static const List<Locale> supported = [
    Locale('en'),
    Locale('si'),
    Locale('ta'),
  ];

  Locale _locale = _fallback;
  Locale get locale => _locale;

  // Track which user this provider's locale is currently bound to.
  String? _currentUserId;
  String get _effectiveUserId => _currentUserId ?? _guestSuffix;
  String get _prefKey => '$_prefPrefix$_effectiveUserId';

  String get currentLanguageCode => _locale.languageCode;

  LocaleProvider() {
    // Try to pick up the currently-signed-in user on startup.
    final existing = SupabaseConfig.client.auth.currentUser?.id;
    if (existing != null) {
      _currentUserId = existing;
    }
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code != null && supported.any((l) => l.languageCode == code)) {
      _locale = Locale(code);
    } else {
      _locale = _fallback;
    }
    notifyListeners();
  }

  /// Load the saved locale for a specific user. Call this after login.
  Future<void> loadForUser(String userId) async {
    _currentUserId = userId;
    await _load();
  }

  /// Reset to fallback (English) and forget which user we were bound to.
  /// Call this on logout. This does NOT wipe the saved preference from disk —
  /// it stays in SharedPreferences so the next time that user logs in,
  /// loadForUser() restores their language.
  Future<void> clearLocale() async {
    _currentUserId = null;
    _locale = _fallback;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale.languageCode);
  }

  String get currentLanguageName {
    switch (_locale.languageCode) {
      case 'si':
        return 'සිංහල';
      case 'ta':
        return 'தமிழ்';
      default:
        return 'English';
    }
  }

  static String languageName(String code) {
    switch (code) {
      case 'si':
        return 'සිංහල';
      case 'ta':
        return 'தமிழ்';
      default:
        return 'English';
    }
  }

  static String languageFlag(String code) {
    switch (code) {
      case 'si':
        return '🇱🇰';
      case 'ta':
        return '🇱🇰';
      default:
        return '🇬🇧';
    }
  }
}
