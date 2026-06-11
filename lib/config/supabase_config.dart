// ═══════════════════════════════════════════════════════════════
// FILE: lib/config/supabase_config.dart
// UPDATED v18 — Reads from flutter_dotenv instead of hardcoded
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static bool _initialized = false;
  static String _url = '';
  static String _anonKey = '';

  /// The Supabase project URL (e.g. for raw HTTP calls).
  static String get projectUrl => _url;

  /// The Supabase anon/public API key.
  static String get anonKey => _anonKey;

  /// The Supabase client singleton.
  /// Always use this — NEVER use Supabase.instance.client directly.
  static SupabaseClient get client => Supabase.instance.client;

  /// Initialize Supabase with env vars.
  /// Call AFTER dotenv.load() in main().
  static Future<void> initialize() async {
    if (_initialized) return;

    // ── Read from .env using KEY NAMES (not values) ──
    final url = dotenv.env['SUPABASE_URL'] ??
        'https://mgfehxoampnafcyriqzt.supabase.co';

    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    _url = url;
    _anonKey = anonKey;

    if (anonKey.isEmpty) {
      throw Exception(
        'SUPABASE_ANON_KEY not found in .env — '
        'copy .env.example to .env and fill in your values.',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
    );

    _initialized = true;
    debugPrint('✅ Supabase initialized (URL: ${url.substring(0, 30)}...)');
  }
}
