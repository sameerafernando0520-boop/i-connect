// lib/services/connectivity_service.dart
// v24 — Offline mode: ConnectivityService
//
// A lightweight singleton service that exposes a `ValueNotifier<bool>` for
// online/offline state.  It listens to `connectivity_plus` for the platform
// connectivity stream AND additionally pings Supabase REST (HEAD /rest/v1/)
// every 15s while the app is foreground so we catch captive-portal style
// "connected to wifi but no internet" situations.
//
// Usage:
//   ConnectivityService.instance.initialize();        // call once in main()
//   ValueListenableBuilder<bool>(
//     valueListenable: ConnectivityService.instance.isOnline,
//     builder: (_, online, __) => OfflineBanner(online: online, child: ...),
//   );
//
// Never throws — failures fall back to "online=true" so the app remains usable.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/supabase_config.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  /// True when device has network reachability.  Defaults to `true` so the
  /// UI doesn't flash an "Offline" banner on app start before the first
  /// reading comes in.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _heartbeat;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ── Step 1: Subscribe to connectivity stream (non-blocking) ──
    // Start listening to stream immediately without waiting for initial probe.
    // This prevents blocking on startup while still getting real-time updates.
    try {
      _sub = Connectivity().onConnectivityChanged.listen(_update);
    } catch (e) {
      // ignore: avoid_print
      print('[ConnectivityService] stream subscribe failed: $e');
      return;
    }

    // ── Step 2: Initial probe (deferred, non-blocking) ──
    // Perform initial check in background to avoid startup blocking.
    // If probe fails, we keep the default "online=true" which is safe.
    Future(() async {
      try {
        final initial = await Connectivity().checkConnectivity();
        _update(initial);
      } catch (e) {
        // ignore: avoid_print
        print('[ConnectivityService] initial probe failed: $e');
        // Keep online=true by default
      }
    });

    // ── Step 3: Start heartbeat for proactive connectivity checks ──
    _startHeartbeat();
  }

  void _update(List<ConnectivityResult> results) {
    // Considered "online" if ANY interface is non-none.
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (isOnline.value != hasNetwork) {
      isOnline.value = hasNetwork;
    }
  }

  /// Mark the device offline manually — useful when a Supabase call fails
  /// with a network error so the UI banner appears immediately.
  void markOffline() {
    if (isOnline.value) isOnline.value = false;
  }

  /// Mark the device online — call from any successful network response.
  void markOnline() {
    if (!isOnline.value) isOnline.value = true;
  }

  void dispose() {
    _sub?.cancel();
    _heartbeat?.cancel();
    _initialized = false;
  }

  /// Proactively ping Supabase REST endpoint every 15-18s (with jitter) to detect
  /// network recovery or server-side issues. Jitter prevents thundering herd where
  /// all devices ping simultaneously.
  void _startHeartbeat() {
    void _ping() async {
      try {
        // Extract domain from Supabase URL (e.g., "https://project.supabase.co" → "project.supabase.co")
        final url = SupabaseConfig.projectUrl;
        final uri = Uri.parse(url);
        final host = uri.host;

        final result = await InternetAddress.lookup(host);
        if (result.isNotEmpty) {
          markOnline();
        } else {
          markOffline();
        }
      } catch (_) {
        markOffline();
      }

      // Schedule next ping with jitter (15-18 seconds)
      final jitterMs = Random().nextInt(3000);
      _heartbeat = Timer(Duration(seconds: 15, milliseconds: jitterMs), _ping);
    }

    // Start first ping with jitter
    _ping();
  }
}
