// lib/services/safe_network.dart
// v24 — Safe network wrapper
//
// Provides a single canonical way for repositories to:
//   1. Run a Supabase / FCM / HTTP call.
//   2. Cache the result for offline access.
//   3. Fall back to the cache when the call fails because the device is
//      offline (rather than because Supabase returned an error).
//   4. Toggle ConnectivityService.isOnline based on the success/failure.
//
// Usage:
//   final tickets = await SafeNetwork.read<List<Map<String, dynamic>>>(
//     cacheKey: 'tickets:open:${userId}',
//     fetch: () async {
//       final rows = await SupabaseConfig.client.from('service_tickets')...;
//       return List<Map<String, dynamic>>.from(rows as List);
//     },
//   );
//
// Repository code stays compact and consistent.  Pages can show
// `OfflineCacheService.instance.lastUpdatedLabel(key)` to flag stale data.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'offline_cache_service.dart';

class SafeNetwork {
  SafeNetwork._();

  /// Wraps a network read with cache+fallback semantics.
  ///
  /// - Tries `fetch()` first.  On success → caches under [cacheKey] and
  ///   marks ConnectivityService online.
  /// - On a network-shaped exception → returns the cached value (if any)
  ///   and marks ConnectivityService offline.
  /// - On any other exception (HTTP 4xx/5xx, etc.) → rethrows so the
  ///   caller can render an in-page error.
  static Future<T?> read<T>({
    required String cacheKey,
    required Future<T> Function() fetch,
    bool useCacheOnError = true,
  }) async {
    try {
      final live = await fetch();
      ConnectivityService.instance.markOnline();
      // Cache only JSON-serializable shapes (List/Map of primitives).
      if (_isJsonish(live)) {
        await OfflineCacheService.instance.write(cacheKey, live as Object);
      }
      return live;
    } catch (e, st) {
      final isNetwork = _looksLikeNetworkError(e);
      if (isNetwork) {
        ConnectivityService.instance.markOffline();
      }
      if ((isNetwork || useCacheOnError)) {
        final cached = OfflineCacheService.instance.read(cacheKey);
        if (cached != null) {
          debugPrint('[SafeNetwork] $cacheKey → returning cached value');
          return cached as T;
        }
      }
      debugPrint('[SafeNetwork] $cacheKey failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Detects exceptions that mean "the device couldn't reach the server".
  /// Tuned for the Supabase + dart:io stack.
  static bool _looksLikeNetworkError(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HandshakeException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('software caused connection abort') ||
        msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('connection timed out') ||
        msg.contains('connection failed');
  }

  /// True for primitives/Map/List trees we can safely jsonEncode.
  static bool _isJsonish(Object? v) {
    if (v == null) return false;
    if (v is num || v is String || v is bool) return true;
    if (v is List) return v.every(_isJsonish);
    if (v is Map) {
      return v.entries.every((e) => e.key is String && _isJsonish(e.value));
    }
    return false;
  }

  /// Convenience: run a write (insert/update/delete) — does NOT cache, but
  /// still toggles online/offline state on network failures.
  static Future<T> write<T>(Future<T> Function() fn) async {
    try {
      final result = await fn();
      ConnectivityService.instance.markOnline();
      return result;
    } catch (e) {
      if (_looksLikeNetworkError(e)) {
        ConnectivityService.instance.markOffline();
      }
      rethrow;
    }
  }
}
