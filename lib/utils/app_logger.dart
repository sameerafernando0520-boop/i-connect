// lib/utils/app_logger.dart
//
// L10: Structured, release-safe logging facade.
//
// `debugPrint` is gated by `kDebugMode` at the framework level — in a release
// build it's effectively a no-op, which means every stack trace, every failed
// network call, every silent catch block we've been "logging" is thrown away.
// That's fine for noise but disastrous for the kind of error we actually need
// to see post-launch (FCM send failures, Supabase RLS surprises, bad JSON
// from the backend).
//
// This module wraps three levels (debug / info / error) behind a single
// surface. In debug, everything falls through to `debugPrint` with a tag
// prefix so we can grep. In release:
//   - `debug` and `info` are suppressed (no perf cost)
//   - `warn` and `error` are forwarded to `_Sink.report` which routes to
//     Firebase Crashlytics for production crash-reporting.
//
// Usage:
//   AppLogger.info('TicketRepo', 'Fetched 42 tickets');
//   AppLogger.error('TicketRepo', 'Fetch failed', error: e, stack: st);

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AppLogger {
  AppLogger._();

  // Set to true to force release-style filtering in a debug build while
  // testing the release path.
  static const bool _forceReleaseBehavior = false;

  static bool get _isRelease => kReleaseMode || _forceReleaseBehavior;

  // ─── Public API ──────────────────────────────────────────

  /// Verbose diagnostics. Suppressed in release — use for tracing, not for
  /// anything you need to see when things break.
  static void debug(String tag, String message) {
    if (_isRelease) return;
    debugPrint('🔍 [$tag] $message');
  }

  /// Informational milestones (lifecycle events, successful RPCs). Suppressed
  /// in release.
  static void info(String tag, String message) {
    if (_isRelease) return;
    debugPrint('ℹ️  [$tag] $message');
  }

  /// Warnings that shouldn't crash but are worth flagging. In release these
  /// are still reported to the sink at "warning" severity (not treated as
  /// errors, not suppressed).
  static void warn(String tag, String message, {Object? error}) {
    final line = error == null ? message : '$message — $error';
    if (_isRelease) {
      _Sink.report(tag, line, severity: 'warning');
      return;
    }
    debugPrint('⚠️  [$tag] $line');
  }

  /// Genuine errors — user-visible failures, exceptions in async chains,
  /// silent-catch candidates. Always reported to the sink, regardless of
  /// build mode.
  ///
  /// Always prefer `AppLogger.error` over `catch (_) {}` — the whole point of
  /// this module is that we stop losing these.
  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    final line = error == null ? message : '$message — $error';
    _Sink.report(
      tag,
      line,
      severity: 'error',
      error: error,
      stack: stack,
    );
    if (!_isRelease) {
      debugPrint('❌ [$tag] $line');
      if (stack != null) debugPrint(stack.toString());
    }
  }
}

/// Thin abstraction over Firebase Crashlytics. In release builds, warnings
/// and errors are forwarded to the Crashlytics dashboard. In debug builds,
/// everything falls through to `debugPrint` for local visibility.
class _Sink {
  static void report(
    String tag,
    String message, {
    required String severity,
    Object? error,
    StackTrace? stack,
  }) {
    // Always write to debug console (no-op in stripped release).
    debugPrint('🛰️  [$severity][$tag] $message');

    // Only forward to Crashlytics in release — avoids polluting the
    // dashboard during development.
    if (!kReleaseMode) return;

    try {
      final crashlytics = FirebaseCrashlytics.instance;

      // Breadcrumb log for context in the Crashlytics timeline.
      crashlytics.log('[$severity][$tag] $message');

      // Record the actual error if one was provided.
      if (error != null) {
        crashlytics.recordError(
          error,
          stack,
          reason: '[$tag] $message',
          fatal: severity == 'error',
        );
      }
    } catch (e) {
      // Crashlytics may not be initialised yet (e.g. very early startup
      // errors before Firebase.initializeApp completes). Swallow silently —
      // the debugPrint above already captured the message locally.
      debugPrint('🛰️  Crashlytics unavailable: $e');
    }
  }
}
