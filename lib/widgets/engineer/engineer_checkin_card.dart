// lib/widgets/engineer/engineer_checkin_card.dart
// v24 — Engineer self check-in/check-out card
//
// Surfaces on the engineer dashboard.  Three states:
//   1. Not checked in today      → primary "Check In" button.
//   2. Checked in, not checked out → "Check Out" button + shift duration.
//   3. Checked out               → static "Shift complete" summary.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../services/attendance_service.dart';
import '../../utils/time_utils.dart';

const _engAccent = Brand.cyanAccent;
const _engGreen = AdminColors.success;
const _engAmber = AdminColors.warning;

class EngineerCheckinCard extends StatefulWidget {
  const EngineerCheckinCard({super.key});

  @override
  State<EngineerCheckinCard> createState() => _EngineerCheckinCardState();
}

class _EngineerCheckinCardState extends State<EngineerCheckinCard> {
  Map<String, dynamic>? _record;
  bool _loading = true;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // refresh duration counter every minute when checked in
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await AttendanceService.instance.todayRecord();
      if (!mounted) return;
      setState(() {
        _record = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _doCheckIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await AttendanceService.instance.checkIn();
      if (!mounted) return;
      setState(() => _record = r);
      _snack('Checked in at ${TimeUtils.formatTime(DateTime.now())}', _engGreen);
    } catch (e) {
      _snack('Check-in failed: $e', StatusColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doCheckOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await AttendanceService.instance.checkOut();
      if (!mounted) return;
      setState(() => _record = r);
      _snack('Checked out at ${TimeUtils.formatTime(DateTime.now())}', _engAmber);
    } catch (e) {
      _snack('Check-out failed: $e', StatusColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return _shell(
        isDark: isDark,
        accent: _engAccent,
        child: const SizedBox(
          height: 64,
          child: Center(
            child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _engAccent),
            ),
          ),
        ),
      );
    }

    final checkIn = _parse(_record?['check_in_time']);
    final checkOut = _parse(_record?['check_out_time']);

    if (checkOut != null) {
      // State 3: shift complete
      return _shell(
        isDark: isDark,
        accent: _engGreen,
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _engGreen.withAlpha(isDark ? 50 : 30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.task_alt_rounded,
                color: _engGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shift complete',
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : AdminColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(
                  '${TimeUtils.formatTime(checkIn ?? checkOut)} – ${TimeUtils.formatTime(checkOut)} · '
                  '${_duration(checkIn ?? checkOut, checkOut)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ]),
      );
    }

    if (checkIn != null) {
      // State 2: checked in, not out yet
      final dur = _duration(checkIn, DateTime.now());
      return _shell(
        isDark: isDark,
        accent: _engAmber,
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _engAmber.withAlpha(isDark ? 50 : 30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.access_time_filled_rounded,
                color: _engAmber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On shift',
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : AdminColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(
                  'Since ${TimeUtils.formatTime(checkIn)} · $dur',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _doCheckOut,
            style: FilledButton.styleFrom(
              backgroundColor: _engAmber.withAlpha(isDark ? 60 : 30),
              foregroundColor: _engAmber,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _engAmber),
                  )
                : const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Check Out',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }

    // State 1: not checked in yet
    return _shell(
      isDark: isDark,
      accent: _engAccent,
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _engAccent.withAlpha(isDark ? 50 : 30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.fingerprint_rounded,
              color: _engAccent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ready to start the day?',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : AdminColors.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text('Tap Check In to mark your arrival',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSecondary,
                  )),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _doCheckIn,
          style: FilledButton.styleFrom(
            backgroundColor: _engAccent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.login_rounded, size: 16),
          label: const Text('Check In',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _shell({
    required bool isDark,
    required Color accent,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withAlpha(isDark ? 80 : 55),
            width: 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: accent.withAlpha(20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: child,
      ),
    );
  }

  DateTime? _parse(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _duration(DateTime start, DateTime end) {
    final mins = end.difference(start).inMinutes;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
