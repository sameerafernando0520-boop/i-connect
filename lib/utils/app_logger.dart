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
//   - `error` is forwarded to `_Sink.report` which today just does a
//     gated debugPrint, but is the single insertion point for Sentry /
//     Crashlytics once a sink is chosen.
//
// Usage:
//   AppLogger.info('TicketRepo', 'Fetched 42 tickets');
//   AppLogger.error('TicketRepo', 'Fetch failed', error: e, stack: st);

import 'package:flutter/foundation.dart';

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

/// Thin abstraction over the eventual crash-reporter. Today this is a
/// `debugPrint`; when Sentry/Crashlytics is wired up, replace the body of
/// `report` with the SDK call and nothing at the call sites needs to change.
class _Sink {
  static void report(
    String tag,
    String message, {
    required String severity,
    Object? error,
    StackTrace? stack,
  }) {
    // TODO(crash-reporter): route to Sentry/Crashlytics here.
    //   Sentry:      Sentry.captureException(error, stackTrace: stack, ...)
    //   Crashlytics: FirebaseCrashlytics.instance.recordError(error, stack,
    //                  reason: '[$tag] $message', fatal: severity=='error');
    //
    // For now, use debugPrint which survives in `flutter logs` during staged
    // release builds and is a no-op in a fully stripped release.
    debugPrint('🛰️  [$severity][$tag] $message');
  }
}
