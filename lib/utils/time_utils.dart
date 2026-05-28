// ═══════════════════════════════════════════════════════════════
// FILE: lib/utils/time_utils.dart
// UPDATED v18 — Added localized variants of key methods.
//   Original methods kept for backward compatibility.
//   Localized methods accept S (AppLocalizations) instance.
// ═══════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';
import 'package:i_connect/l10n/s.dart';

class TimeUtils {
  TimeUtils._();

  // ═════════════════════════════════════════════════════════════
  // LOCALIZED METHODS (pass S.of(context) from the call-site)
  // ═════════════════════════════════════════════════════════════

  /// Localized relative time — "මිනිත්තු 5කට පෙර", "2h ago", etc.
  static String getTimeAgoL(DateTime dateTime, S t) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return t.timeJustNow;
    if (diff.inMinutes < 60) return t.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return t.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return t.timeDaysAgo(diff.inDays);
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return t.timeAgo(t.timeWeeks(weeks));
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return t.timeAgo(t.timeMonths(months));
    }
    final years = (diff.inDays / 365).floor();
    return t.timeAgo('${years}y');
  }

  /// Localized greeting — "காலை வணக்கம்", "සුභ සන්ධ්‍යාවක්", etc.
  static String getGreetingL(S t) {
    final hour = DateTime.now().hour;
    if (hour < 12) return t.homeGoodMorning;
    if (hour < 17) return t.homeGoodAfternoon;
    return t.homeGoodEvening;
  }

  /// Localized date separator for chat — "අද", "நேற்று", or formatted date.
  static String formatDateSeparatorL(DateTime dt, S t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return t.timeToday;
    if (diff == 1) return t.timeYesterday;
    if (diff < 7) return DateFormat('EEEE').format(dt);
    if (dt.year == now.year) return DateFormat('MMM d').format(dt);
    return DateFormat('MMM d, yyyy').format(dt);
  }

  // ═════════════════════════════════════════════════════════════
  // ORIGINAL METHODS (kept for backward compatibility)
  // ═════════════════════════════════════════════════════════════

  /// Relative time ("2h ago", "3d ago") — English only.
  /// Prefer [getTimeAgoL] for localized output.
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  /// "Good Morning" / "Good Afternoon" / "Good Evening" — English only.
  /// Prefer [getGreetingL] for localized output.
  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ─── "Jan 2024" ──────────────────────────────────────────
  static String formatMonthYear(DateTime dt) {
    return DateFormat('MMM yyyy').format(dt);
  }

  // ─── "January 15, 2024" ──────────────────────────────────
  static String formatDateFull(DateTime dt) {
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  // ─── "Jan 15, 2024 2:30 PM" ──────────────────────────────
  static String formatDateTime(DateTime dt) {
    return DateFormat('MMM d, yyyy h:mm a').format(dt);
  }

  // ─── "2:30 PM" ───────────────────────────────────────────
  static String formatTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  // ─── Chat message time: "2:30 PM" ────────────────────────
  static String formatMessageTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  // ─── Chat date separator: "Today" / "Yesterday" / date ───
  /// English only. Prefer [formatDateSeparatorL] for localized output.
  static String formatDateSeparator(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(dt);
    if (dt.year == now.year) return DateFormat('MMM d').format(dt);
    return DateFormat('MMM d, yyyy').format(dt);
  }

  // ─── Are two DateTimes on different calendar days? ────────
  static bool isDifferentDay(DateTime a, DateTime b) =>
      a.year != b.year || a.month != b.month || a.day != b.day;

  // ─── Duration → "2h 30m" / "45m" / "3d 2h" ──────────────
  static String formatDuration(Duration d) {
    if (d.inDays > 0) {
      final hours = d.inHours % 24;
      return hours > 0 ? '${d.inDays}d ${hours}h' : '${d.inDays}d';
    }
    if (d.inHours > 0) {
      final mins = d.inMinutes % 60;
      return mins > 0 ? '${d.inHours}h ${mins}m' : '${d.inHours}h';
    }
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  // ─── "2024-01-15" (ISO date only) ────────────────────────
  static String formatDateShort(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }
}