// lib/services/offline_cache_service.dart
// v24 — Read-only offline cache layer
//
// A thin wrapper around SharedPreferences that stores JSON payloads with a
// TTL.  Used by repositories / pages to:
//   1. On successful network read, write the response to cache.
//   2. On failed network read (or while loading), read from cache as fallback.
//
// API:
//   await OfflineCacheService.instance.write('tickets:open', listJson);
//   final cached = OfflineCacheService.instance.read('tickets:open');
//   final stale  = OfflineCacheService.instance.isStale('tickets:open');
//
// Each cache entry is wrapped:
//   { "ts": <unix-ms>, "data": <payload> }
//
// TTL is advisory — `read()` always returns whatever's stored.  Use `isStale()`
// to decide whether to show a "Showing cached data" badge.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  OfflineCacheService._();
  static final OfflineCacheService instance = OfflineCacheService._();

  static const String _prefix = 'oc_';
  static const Duration defaultTtl = Duration(minutes: 30);

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _ensure() async {
    if (_prefs == null) await initialize();
  }

  /// Write `payload` (Map or List) to cache under `key`.
  Future<void> write(String key, Object payload) async {
    await _ensure();
    try {
      final envelope = jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': payload,
      });
      await _prefs!.setString('$_prefix$key', envelope);
    } catch (e) {
      debugPrint('[OfflineCache] write($key) failed: $e');
    }
  }

  /// Return cached payload typed as `T`, or `null` if absent / corrupt.
  T? read<T>(String key) {
    if (_prefs == null) return null;
    final raw = _prefs!.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final env = jsonDecode(raw) as Map<String, dynamic>;
      final data = env['data'];
      if (data is T) {
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the cache write timestamp, or `null` if absent.
  DateTime? readTimestamp(String key) {
    if (_prefs == null) return null;
    final raw = _prefs!.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final env = jsonDecode(raw) as Map<String, dynamic>;
      final ts = env['ts'] as int?;
      return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
    } catch (_) {
      return null;
    }
  }

  /// True if a cached value exists but is older than `ttl`.
  bool isStale(String key, {Duration ttl = defaultTtl}) {
    final ts = readTimestamp(key);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > ttl;
  }

  /// Removes a single cache entry.
  Future<void> invalidate(String key) async {
    await _ensure();
    await _prefs!.remove('$_prefix$key');
  }

  /// Clear every entry written by this service (does NOT touch other prefs).
  Future<void> clearAll() async {
    await _ensure();
    final keys = _prefs!.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await _prefs!.remove(k);
    }
  }

  /// Returns a human "Updated X ago" string from the cache timestamp.
  String? lastUpdatedLabel(String key) {
    final ts = readTimestamp(key);
    if (ts == null) return null;
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }
}
