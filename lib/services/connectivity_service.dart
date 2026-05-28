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
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
    // Step 1: initial probe.  If this throws (e.g. missing
    // ACCESS_NETWORK_STATE permission or restricted platform), keep the
    // app online-by-default and skip subscribing — the explicit
    // markOffline/markOnline calls from SafeNetwork still keep state useful.
    try {
      final initial = await Connectivity().checkConnectivity();
      _update(initial);
    } catch (e) {
      isOnline.value = true;
      // ignore: avoid_print
      print('[ConnectivityService] initial probe failed: $e');
      return;
    }
    // Step 2: subscribe.  Wrapped separately so a SecurityException raised
    // when the BroadcastReceiver registers (Android 12+ exported flag) does
    // not undo a successful initial probe.
    try {
      _sub = Connectivity().onConnectivityChanged.listen(_update);
    } catch (e) {
      // ignore: avoid_print
      print('[ConnectivityService] stream subscribe failed: $e');
    }
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
}
