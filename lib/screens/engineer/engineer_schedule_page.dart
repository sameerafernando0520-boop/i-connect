import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter,
         PostgresChangeFilterType;
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import 'engineer_create_schedule_page.dart';

const Color _engAccent = Color(0xFF00B4D8);
const Color _engAccentDark = Color(0xFF0096B7);

// ── Schedule Helpers ──

Color _typeColor(String? type) {
  switch (type) {
    case 'preventive':
      return const Color(0xFF3B82F6);
    case 'repair':
      return const Color(0xFFEF4444);
    case 'inspection':
      return const Color(0xFF14B8A6);
    case 'installation':
      return const Color(0xFF8B5CF6);
    case 'warranty_visit':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF6B7280);
  }
}

String _typeLabel(String? type) {
  switch (type) {
    case 'preventive':
      return 'Preventive';
    case 'repair':
      return 'Repair';
    case 'inspection':
      return 'Inspection';
    case 'installation':
      return 'Installation';
    case 'warranty_visit':
      return 'Warranty';
    default:
      return type ?? 'Unknown';
  }
}

IconData _typeIcon(String? type) {
  switch (type) {
    case 'preventive':
      return Icons.build_circle_outlined;
    case 'repair':
      return Icons.handyman;
    case 'inspection':
      return Icons.search;
    case 'installation':
      return Icons.precision_manufacturing;
    case 'warranty_visit':
      return Icons.verified_user;
    default:
      return Icons.event;
  }
}

Color _statusColor(String? status) {
  switch (status) {
    case 'requested':
      return const Color(0xFFF59E0B);
    case 'scheduled':
      return const Color(0xFF3B82F6);
    case 'confirmed':
      return const Color(0xFF6366F1);
    case 'in_progress':
      return const Color(0xFFF97316);
    case 'completed':
      return const Color(0xFF22C55E);
    case 'cancelled':
      return const Color(0xFFEF4444);
    case 'rescheduled':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFF6B7280);
  }
}

String _statusLabel(String? status) {
  switch (status) {
    case 'requested':
      return 'Requested';
    case 'scheduled':
      return 'Scheduled';
    case 'confirmed':
      return 'Confirmed';
    case 'in_progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'rescheduled':
      return 'Rescheduled';
    default:
      return status ?? 'Unknown';
  }
}

String _fmtTime(String? t) {
  if (t == null || t.isEmpty) return '';
  final p = t.split(':');
  if (p.length < 2) return t;
  final h = int.tryParse(p[0]) ?? 0;
  final m = int.tryParse(p[1]) ?? 0;
  final period = h >= 12 ? 'PM' : 'AM';
  final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
  return '$dh:${m.toString().padLeft(2, '0')} $period';
}

String _endTimeFromDuration(String? startTime, int? duration) {
  if (startTime == null || duration == null) return '';
  final parts = startTime.split(':');
  if (parts.length < 2) return '';
  final startMin =
      (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  final endMin = startMin + duration;
  final h = (endMin ~/ 60) % 24;
  final m = endMin % 60;
  final period = h >= 12 ? 'PM' : 'AM';
  final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
  return '$dh:${m.toString().padLeft(2, '0')} $period';
}

// ─────────────────────────────────────────────────────────────

class EngineerSchedulePage extends StatefulWidget {
  const EngineerSchedulePage({super.key});

  @override
  State<EngineerSchedulePage> createState() => _EngineerSchedulePageState();
}

class _EngineerSchedulePageState extends State<EngineerSchedulePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _todaySchedules = [];
  List<Map<String, dynamic>> _upcomingSchedules = [];
  List<Map<String, dynamic>> _completedSchedules = [];
  bool _loading = true;
  bool _acting = false;
  RealtimeChannel? _scheduleChannel;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
    _subscribeSchedules();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _scheduleChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  void _subscribeSchedules() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    _scheduleChannel = SupabaseConfig.client.channel('eng-schedules-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'service_schedules',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'engineer_id',
          value: userId,
        ),
        callback: (_) => _debouncedReload(),
      )
      ..subscribe();
  }

  void _debouncedReload() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _load();
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final todayStr = _fmtDate(now);
      final futureEnd = _fmtDate(now.add(const Duration(days: 90)));
      final pastStart = _fmtDate(now.subtract(const Duration(days: 30)));

      // Fetch all schedules in one query
      final data = await SupabaseConfig.client
          .from('service_schedules')
          .select('''
            id, title, description, schedule_type, status,
            scheduled_date, scheduled_time, estimated_duration,
            service_location, is_recurring, recurrence_rule,
            customer_notes, admin_notes, engineer_notes,
            service_report, customer_rating, customer_feedback,
            confirmed_at, started_at, completed_at, cancelled_at,
            cancellation_reason, created_at,
            customer:users!customer_id(id, full_name, phone_number, profile_photo, company_name, email, address, city),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number)
            )
          ''')
          .eq('engineer_id', userId)
          .gte('scheduled_date', pastStart)
          .lte('scheduled_date', futureEnd)
          .order('scheduled_date')
          .order('scheduled_time');

      final schedules = List<Map<String, dynamic>>.from(data);
      final today = <Map<String, dynamic>>[];
      final upcoming = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];

      for (final s in schedules) {
        final dateStr = s['scheduled_date'] as String? ?? '';
        final status = s['status'] as String? ?? '';

        if (status == 'completed' ||
            status == 'cancelled' ||
            status == 'rescheduled') {
          completed.add(s);
        } else if (dateStr == todayStr) {
          today.add(s);
        } else if (dateStr.compareTo(todayStr) > 0) {
          upcoming.add(s);
        } else {
          // Past but not completed — overdue, show in today
          today.add(s);
        }
      }

      // Sort completed most-recent first
      completed.sort((a, b) {
        final ad = a['scheduled_date'] as String? ?? '';
        final bd = b['scheduled_date'] as String? ?? '';
        return bd.compareTo(ad);
      });

      if (!mounted) return;
      setState(() {
        _todaySchedules = today;
        _upcomingSchedules = upcoming;
        _completedSchedules = completed;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load engineer schedules error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Failed to load schedules: $e', isError: true);
    }
  }

  // ── Status Updates ──

  Future<void> _confirmSchedule(String id) async {
    await _updateStatus(
        id, 'confirmed', {'confirmed_at': DateTime.now().toUtc().toIso8601String()});
  }

  Future<void> _startService(String id) async {
    await _updateStatus(
        id, 'in_progress', {'started_at': DateTime.now().toUtc().toIso8601String()});
  }

  Future<void> _completeService(Map<String, dynamic> schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reportCtrl = TextEditingController();
    final notesCtrl = TextEditingController(
      text: schedule['engineer_notes'] as String? ?? '',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Complete Service',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add your service report before marking as complete.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 20),

                // Service Report
                Text(
                  'Service Report *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reportCtrl,
                  maxLines: 4,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Describe work performed, parts replaced, findings...',
                    hintStyle: TextStyle(
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),

                // Engineer Notes
                Text(
                  'Engineer Notes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Internal notes (not visible to customer)...',
                    hintStyle: TextStyle(
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          side: BorderSide(
                            color:
                                isDark ? Brand.darkBorder : Brand.borderLight,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (reportCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content: const Row(children: [
                                  Icon(Icons.error_outline,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Please add a service report'),
                                ]),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(sheetCtx, true);
                        },
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: const Text('Complete'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (result != true || !mounted) {
      reportCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    await _updateStatus(schedule['id'] as String, 'completed', {
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'service_report': reportCtrl.text.trim(),
      'engineer_notes':
          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    });

    reportCtrl.dispose();
    notesCtrl.dispose();
  }

  // ── Cancel Schedule ──

  Future<void> _cancelSchedule(Map<String, dynamic> schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasonCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withAlpha(isDark ? 30 : 20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cancel_outlined,
                          color: Color(0xFFEF4444), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cancel Service',
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700,
                                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                              )),
                          const SizedBox(height: 2),
                          Text('This will notify the admin and customer.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Reason for cancellation *',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Parts unavailable, scheduling conflict, etc...',
                    hintStyle: TextStyle(
                      color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                          side: BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Keep'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (reasonCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content: const Row(children: [
                                  Icon(Icons.error_outline, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Please provide a cancellation reason'),
                                ]),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(sheetCtx, true);
                        },
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Cancel Service'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (result != true || !mounted) {
      reasonCtrl.dispose();
      return;
    }

    await _updateStatus(schedule['id'] as String, 'cancelled', {
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      'cancellation_reason': reasonCtrl.text.trim(),
    });
    reasonCtrl.dispose();
  }

  // ── Reschedule ──

  Future<void> _rescheduleService(Map<String, dynamic> schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final existingDate = schedule['scheduled_date'] as String? ?? '';
    final existingTime = schedule['scheduled_time'] as String?;

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    try {
      selectedDate = DateTime.parse(existingDate);
      if (selectedDate.isBefore(DateTime.now())) {
        selectedDate = DateTime.now().add(const Duration(days: 1));
      }
    } catch (_) {}

    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    if (existingTime != null) {
      final parts = existingTime.split(':');
      if (parts.length >= 2) {
        selectedTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    final reasonCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withAlpha(isDark ? 30 : 20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.schedule_send,
                              color: Color(0xFF8B5CF6), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text('Reschedule Service',
                            style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700,
                              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                            )),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Date picker
                    Text('New Date',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        )),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 18,
                                color: isDark ? _engAccent : _engAccentDark),
                            const SizedBox(width: 10),
                            Text(
                              TimeUtils.formatDateShort(selectedDate),
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.chevron_right,
                                size: 20,
                                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Time picker
                    Text('New Time',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        )),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setSheetState(() => selectedTime = picked);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 18,
                                color: isDark ? _engAccent : _engAccentDark),
                            const SizedBox(width: 10),
                            Text(
                              selectedTime.format(ctx),
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.chevron_right,
                                size: 20,
                                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Reason
                    Text('Reason (optional)',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        )),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      style: TextStyle(
                        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Why are you rescheduling?',
                        hintStyle: TextStyle(
                          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                        ),
                        filled: true,
                        fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx, {
                            'date': selectedDate,
                            'time': selectedTime,
                            'reason': reasonCtrl.text.trim(),
                          });
                        },
                        icon: const Icon(Icons.schedule_send, size: 20),
                        label: const Text('Reschedule',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    reasonCtrl.dispose();
    if (result == null || !mounted) return;

    final newDate = result['date'] as DateTime;
    final newTime = result['time'] as TimeOfDay;
    final reason = result['reason'] as String;
    final dateStr =
        '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}:00';

    await _updateStatus(schedule['id'] as String, 'rescheduled', {
      'scheduled_date': dateStr,
      'scheduled_time': timeStr,
      'cancellation_reason':
          reason.isNotEmpty ? 'Rescheduled: $reason' : 'Rescheduled by engineer',
    });
  }

  // ── Contact Customer ──

  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      _snack('Cannot open phone dialer', isError: true);
    }
  }

  Future<void> _emailCustomer(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      _snack('Cannot open email app', isError: true);
    }
  }

  Future<void> _updateStatus(
      String id, String newStatus, Map<String, dynamic> extraFields) async {
    setState(() => _acting = true);
    try {
      final updates = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        ...extraFields,
      };

      await SupabaseConfig.client
          .from('service_schedules')
          .update(updates)
          .eq('id', id);

      if (!mounted) return;
      _snack('Status updated to ${_statusLabel(newStatus)}');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ── Add Engineer Notes ──

  Future<void> _editNotes(Map<String, dynamic> schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController(
      text: schedule['engineer_notes'] as String? ?? '',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Engineer Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Internal notes — not visible to the customer.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  maxLines: 5,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add your notes here...',
                    hintStyle: TextStyle(
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetCtx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _engAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save Notes',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (result != true || !mounted) {
      ctrl.dispose();
      return;
    }

    try {
      await SupabaseConfig.client.from('service_schedules').update({
        'engineer_notes': ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', schedule['id']);

      if (!mounted) return;
      _snack('Notes saved');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Failed: $e', isError: true);
    }
    ctrl.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        title: const Text('My Schedule'),
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        foregroundColor: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? _engAccent : _engAccentDark,
          unselectedLabelColor:
              isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          indicatorColor: isDark ? _engAccent : _engAccentDark,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
          tabs: [
            Tab(text: 'Today (${_todaySchedules.length})'),
            Tab(text: 'Upcoming (${_upcomingSchedules.length})'),
            Tab(text: 'Done (${_completedSchedules.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => const EngineerCreateSchedulePage(),
            ),
          );
          if (result == true && mounted) _load();
        },
        backgroundColor: _engAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Schedule',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? _buildLoadingState(isDark)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTodayTab(isDark),
                _buildListTab(_upcomingSchedules, isDark,
                    emptyIcon: Icons.event_available,
                    emptyTitle: 'No upcoming schedules',
                    emptyMsg: 'You\'re all caught up!'),
                _buildListTab(_completedSchedules, isDark,
                    emptyIcon: Icons.history,
                    emptyTitle: 'No completed services',
                    emptyMsg: 'Completed services will appear here'),
              ],
            ),
    );
  }

  // ── Today Tab (Timeline) ──

  Widget _buildTodayTab(bool isDark) {
    if (_todaySchedules.isEmpty) {
      return RefreshIndicator(
        color: _engAccent,
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _engAccent.withAlpha(isDark ? 25 : 20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_available,
                        size: 40, color: isDark ? _engAccent : _engAccentDark),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No services today',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enjoy your free day!',
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _engAccent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── Summary Bar ──
          _buildTodaySummary(isDark),
          const SizedBox(height: 16),

          // ── Timeline ──
          ...List.generate(_todaySchedules.length, (i) {
            return _buildTimelineItem(_todaySchedules[i], isDark,
                isFirst: i == 0, isLast: i == _todaySchedules.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildTodaySummary(bool isDark) {
    final total = _todaySchedules.length;
    final inProgress =
        _todaySchedules.where((s) => s['status'] == 'in_progress').length;
    final pending = _todaySchedules
        .where((s) =>
            s['status'] == 'scheduled' ||
            s['status'] == 'confirmed' ||
            s['status'] == 'requested')
        .length;

    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good Morning'
        : (now.hour < 17 ? 'Good Afternoon' : 'Good Evening');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [_engAccent.withAlpha(38), _engAccentDark.withAlpha(25)]
              : [_engAccent.withAlpha(26), _engAccentDark.withAlpha(15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _engAccent.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting 👋',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You have $total service${total == 1 ? '' : 's'} today',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _summaryChip(Icons.pending_actions, '$pending Pending',
                  const Color(0xFF3B82F6), isDark),
              const SizedBox(width: 12),
              _summaryChip(Icons.play_circle_outline, '$inProgress Active',
                  const Color(0xFFF97316), isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ── Timeline Item ──

  Widget _buildTimelineItem(
    Map<String, dynamic> schedule,
    bool isDark, {
    required bool isFirst,
    required bool isLast,
  }) {
    final type = schedule['schedule_type'] as String? ?? '';
    final status = schedule['status'] as String? ?? '';
    final title = schedule['title'] as String? ?? 'Service Visit';
    final time = schedule['scheduled_time'] as String?;
    final duration = schedule['estimated_duration'] as int?;
    final location = schedule['service_location'] as String?;
    final customer = schedule['customer'] as Map<String, dynamic>?;
    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final companyName = customer?['company_name'] as String? ?? '';
    final phone = customer?['phone_number'] as String? ?? '';
    final machine = schedule['machine'] as Map<String, dynamic>?;
    final catalog = machine?['catalog'] as Map<String, dynamic>?;
    final machineName = catalog?['machine_name'] as String?;
    final serialNumber = machine?['serial_number'] as String?;
    final customerNotes = schedule['customer_notes'] as String? ?? '';
    final adminNotes = schedule['admin_notes'] as String? ?? '';

    final isActive = status == 'in_progress';
    final lineColor = isActive
        ? _engAccent
        : (isDark ? Brand.darkBorderLight : Brand.borderLight);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline Line + Dot ──
          SizedBox(
            width: 32,
            child: Column(
              children: [
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 12,
                    color: lineColor,
                  ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isActive ? _engAccent : _typeColor(type).withAlpha(128),
                    border: Border.all(
                      color: isActive ? _engAccent : _typeColor(type),
                      width: 2,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                                color: _engAccent.withAlpha(77), blurRadius: 8)
                          ]
                        : null,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : lineColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── Card ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive
                        ? _engAccent.withAlpha(102)
                        : (isDark ? Brand.darkBorder : Brand.borderLight),
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: _engAccent.withAlpha(isDark ? 20 : 15),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time + Status
                          Row(
                            children: [
                              if (time != null) ...[
                                Icon(Icons.access_time,
                                    size: 14,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight),
                                const SizedBox(width: 4),
                                Text(
                                  '${_fmtTime(time)}${duration != null ? ' – ${_endTimeFromDuration(time, duration)}' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              _buildBadge(_statusLabel(status),
                                  _statusColor(status), isDark),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Title + Type
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _typeColor(type)
                                      .withAlpha(isDark ? 38 : 26),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(_typeIcon(type),
                                    size: 18, color: _typeColor(type)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      _typeLabel(type),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _typeColor(type),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Customer
                          _infoRow(
                              Icons.person_outline,
                              customerName,
                              companyName.isNotEmpty ? companyName : null,
                              isDark),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => _callCustomer(phone),
                              child: _infoRow(Icons.phone_outlined, phone, 'Tap to call', isDark),
                            ),
                          ],

                          // Machine
                          if (machineName != null) ...[
                            const SizedBox(height: 6),
                            _infoRow(
                              Icons.precision_manufacturing_outlined,
                              machineName,
                              serialNumber != null
                                  ? 'S/N: $serialNumber'
                                  : null,
                              isDark,
                            ),
                          ],

                          // Location
                          if (location != null && location.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _infoRow(Icons.location_on_outlined, location, null,
                                isDark),
                          ],

                          // Notes
                          if (customerNotes.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withAlpha(isDark ? 20 : 12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.note_alt_outlined,
                                      size: 14, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Customer Notes',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFF59E0B),
                                            )),
                                        const SizedBox(height: 2),
                                        Text(customerNotes,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Brand.darkTextSecondary
                                                  : Brand.royalBlueDark,
                                            )),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          if (adminNotes.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    Brand.royalBlue.withAlpha(isDark ? 20 : 12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.admin_panel_settings,
                                      size: 14,
                                      color: isDark
                                          ? Brand.royalBlueGlow
                                          : Brand.royalBlue),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Admin Notes',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Brand.royalBlueGlow
                                                  : Brand.royalBlue,
                                            )),
                                        const SizedBox(height: 2),
                                        Text(adminNotes,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Brand.darkTextSecondary
                                                  : Brand.royalBlueDark,
                                            )),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ── Action Buttons ──
                    if (!_isTerminal(status)) ...[
                      Divider(
                        height: 24,
                        color: isDark ? Brand.darkBorder : Brand.borderLight,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: _buildCardActions(schedule, isDark),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card Actions ──

  Widget _buildCardActions(Map<String, dynamic> schedule, bool isDark) {
    final status = schedule['status'] as String? ?? '';
    final id = schedule['id'] as String;
    final customer = schedule['customer'] as Map<String, dynamic>?;
    final phone = customer?['phone_number'] as String? ?? '';
    final email = customer?['email'] as String? ?? '';

    return Column(
      children: [
        // ── Row 1: Contact + Notes ──
        Row(
          children: [
            // Call customer
            if (phone.isNotEmpty)
              _actionChip(
                icon: Icons.phone_outlined,
                label: 'Call',
                color: const Color(0xFF22C55E),
                isDark: isDark,
                onTap: _acting ? null : () => _callCustomer(phone),
              ),
            if (phone.isNotEmpty) const SizedBox(width: 6),

            // Email customer
            if (email.isNotEmpty)
              _actionChip(
                icon: Icons.mail_outline,
                label: 'Email',
                color: const Color(0xFF3B82F6),
                isDark: isDark,
                onTap: _acting ? null : () => _emailCustomer(email),
              ),
            if (email.isNotEmpty) const SizedBox(width: 6),

            // Notes
            _actionChip(
              icon: Icons.edit_note,
              label: 'Notes',
              color: isDark ? _engAccent : _engAccentDark,
              isDark: isDark,
              onTap: _acting ? null : () => _editNotes(schedule),
            ),

            const Spacer(),

            // Overflow menu (cancel / reschedule)
            if (status != 'in_progress')
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz,
                    size: 20,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                color: isDark ? Brand.darkCardElevated : Colors.white,
                elevation: isDark ? 4 : 2,
                onSelected: (v) {
                  if (v == 'cancel') _cancelSchedule(schedule);
                  if (v == 'reschedule') _rescheduleService(schedule);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'reschedule',
                    child: Row(children: [
                      const Icon(Icons.schedule_send,
                          size: 18, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 10),
                      Text('Reschedule',
                          style: TextStyle(
                            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                          )),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'cancel',
                    child: Row(children: [
                      const Icon(Icons.cancel_outlined,
                          size: 18, color: Color(0xFFEF4444)),
                      const SizedBox(width: 10),
                      Text('Cancel',
                          style: TextStyle(
                            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                          )),
                    ]),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Row 2: Primary Action ──
        Row(
          children: [
            // Status-specific action — full width
            if (status == 'scheduled' || status == 'requested')
              Expanded(
                child: FilledButton.icon(
                  onPressed: _acting ? null : () => _confirmSchedule(id),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirm', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),

            if (status == 'confirmed')
              Expanded(
                child: FilledButton.icon(
                  onPressed: _acting ? null : () => _startService(id),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Start Service', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),

            if (status == 'in_progress') ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _acting ? null : () => _cancelSchedule(schedule),
                  icon: const Icon(Icons.cancel_outlined, size: 16,
                      color: Color(0xFFEF4444)),
                  label: const Text('Cancel',
                      style: TextStyle(fontSize: 13, color: Color(0xFFEF4444))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444), width: 0.8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _acting ? null : () => _completeService(schedule),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Complete', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 25 : 15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  // ── Generic List Tab ──

  Widget _buildListTab(
    List<Map<String, dynamic>> items,
    bool isDark, {
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMsg,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: _engAccent,
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Center(
              child: Column(
                children: [
                  Icon(emptyIcon,
                      size: 56,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                  const SizedBox(height: 14),
                  Text(emptyTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      )),
                  const SizedBox(height: 4),
                  Text(emptyMsg,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      )),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _engAccent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildCompactCard(items[i], isDark),
      ),
    );
  }

  // ── Compact Card (Upcoming + Done) ──

  Widget _buildCompactCard(Map<String, dynamic> schedule, bool isDark) {
    final type = schedule['schedule_type'] as String? ?? '';
    final status = schedule['status'] as String? ?? '';
    final title = schedule['title'] as String? ?? 'Service Visit';
    final dateStr = schedule['scheduled_date'] as String? ?? '';
    final time = schedule['scheduled_time'] as String?;

    final location = schedule['service_location'] as String?;
    final customer = schedule['customer'] as Map<String, dynamic>?;
    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final companyName = customer?['company_name'] as String? ?? '';
    final rating = schedule['customer_rating'] as int?;
    final isCompleted = status == 'completed';

    DateTime? date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {}

    // Days until for upcoming
    String daysLabel = '';
    if (date != null && !_isTerminal(status)) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff =
          DateTime(date.year, date.month, date.day).difference(today).inDays;
      if (diff == 0) {
        daysLabel = 'Today';
      } else if (diff == 1) {
        daysLabel = 'Tomorrow';
      } else if (diff > 0) {
        daysLabel = 'In $diff days';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Color bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _typeColor(type),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + badges
                    Row(
                      children: [
                        if (date != null) ...[
                          Text(
                            TimeUtils.formatDateShort(date),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                          if (time != null) ...[
                            Text(' · ',
                                style: TextStyle(
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight,
                                )),
                            Text(_fmtTime(time),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                )),
                          ],
                        ],
                        if (daysLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _engAccent.withAlpha(isDark ? 30 : 20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(daysLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _engAccent)),
                          ),
                        ],
                        const Spacer(),
                        _buildBadge(
                            _statusLabel(status), _statusColor(status), isDark),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Title
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Customer
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$customerName${companyName.isNotEmpty ? ' · $companyName' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Location
                    if (location != null && location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Rating (for completed)
                    if (isCompleted && rating != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ...List.generate(
                              5,
                              (i) => Icon(
                                    i < rating
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    size: 16,
                                    color: const Color(0xFFF59E0B),
                                  )),
                          const SizedBox(width: 6),
                          Text('Customer rated $rating/5',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight,
                              )),
                        ],
                      ),
                    ],

                    // Action buttons for upcoming
                    if (!_isTerminal(status)) ...[
                      const SizedBox(height: 10),
                      _buildCardActions(schedule, isDark),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared Widgets ──

  Widget _infoRow(
      IconData icon, String primary, String? secondary, bool isDark) {
    return Row(
      children: [
        Icon(icon,
            size: 14,
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
              children: [
                TextSpan(text: primary),
                if (secondary != null)
                  TextSpan(
                    text: ' · $secondary',
                    style: TextStyle(
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 38 : 26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  bool _isTerminal(String? status) =>
      status == 'completed' || status == 'cancelled' || status == 'rescheduled';

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: isDark ? _engAccent : _engAccentDark,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading schedule...',
            style: TextStyle(
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }
}
