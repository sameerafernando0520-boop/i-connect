import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../services/points_service.dart';
import '../../utils/time_utils.dart';
import 'request_service_page.dart';

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

String _statusDescription(String? status) {
  switch (status) {
    case 'requested':
      return 'Your request has been submitted and is awaiting confirmation.';
    case 'scheduled':
      return 'Your service has been scheduled. An engineer will be assigned.';
    case 'confirmed':
      return 'Your service is confirmed. The engineer is ready.';
    case 'in_progress':
      return 'The engineer is currently on-site working on your service.';
    case 'completed':
      return 'This service has been completed.';
    case 'cancelled':
      return 'This service was cancelled.';
    case 'rescheduled':
      return 'This service has been rescheduled to a new date.';
    default:
      return '';
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

class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
  bool _loading = true;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

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
            engineer:users!engineer_id(id, full_name, profile_photo),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number)
            )
          ''')
          .eq('customer_id', userId)
          .order('scheduled_date', ascending: false);

      final schedules = List<Map<String, dynamic>>.from(data);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day)
          .toIso8601String()
          .substring(0, 10);

      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];

      for (final s in schedules) {
        final status = s['status'] as String? ?? '';
        final dateStr = s['scheduled_date'] as String? ?? '';

        final isTerminal = status == 'completed' ||
            status == 'cancelled' ||
            status == 'rescheduled';
        final isPast = dateStr.compareTo(today) < 0 && isTerminal;

        if (isTerminal || isPast) {
          past.add(s);
        } else {
          upcoming.add(s);
        }
      }

      // Sort upcoming by date ascending (nearest first)
      upcoming.sort((a, b) {
        final ad = a['scheduled_date'] as String? ?? '';
        final bd = b['scheduled_date'] as String? ?? '';
        final cmp = ad.compareTo(bd);
        if (cmp != 0) return cmp;
        final at = a['scheduled_time'] as String? ?? '';
        final bt = b['scheduled_time'] as String? ?? '';
        return at.compareTo(bt);
      });

      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _past = past;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load schedules error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to load schedules: $e')),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Rating ──

  Future<void> _showRatingSheet(Map<String, dynamic> schedule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int rating = schedule['customer_rating'] as int? ?? 0;
    final feedbackCtrl = TextEditingController(
      text: schedule['customer_feedback'] as String? ?? '',
    );

    final result = await showModalBottomSheet<bool>(
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            isDark ? Brand.darkBorderLight : Brand.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Rate This Service',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'How was your experience?',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Stars
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        return GestureDetector(
                          onTap: () => setSheetState(() => rating = i + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 40,
                              color: i < rating
                                  ? const Color(0xFFF59E0B)
                                  : (isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rating == 0
                          ? 'Tap a star to rate'
                          : [
                              '',
                              'Poor',
                              'Fair',
                              'Good',
                              'Very Good',
                              'Excellent'
                            ][rating],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: rating == 0
                            ? (isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Feedback
                    TextField(
                      controller: feedbackCtrl,
                      maxLines: 3,
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Share your feedback (optional)...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Brand.darkCardElevated
                            : Brand.scaffoldLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed:
                            rating == 0 ? null : () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.royalBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Submit Rating',
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
      },
    );

    if (result != true || !mounted || rating == 0) {
      feedbackCtrl.dispose();
      return;
    }

    try {
      await SupabaseConfig.client.from('service_schedules').update({
        'customer_rating': rating,
        'customer_feedback':
            feedbackCtrl.text.trim().isEmpty ? null : feedbackCtrl.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', schedule['id']);

      // ── Award rating points ──
      PointsService.award(
        'service_rating',
        20,
        'Rated service visit',
        schedule['id'] as String,
        'schedule',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Thank you for your feedback!'),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Brand.lightGreenDark,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to submit rating: $e')),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
    feedbackCtrl.dispose();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: Text(
          'My Schedules',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        foregroundColor: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
          unselectedLabelColor:
              isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          indicatorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
          tabs: [
            Tab(text: 'Upcoming (${_upcoming.length})'),
            Tab(text: 'Past (${_past.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RequestServicePage()),
          ).then((_) {
            if (mounted) _load();
          });
        },
        backgroundColor: Brand.royalBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Request Service'),
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_upcoming, isDark, isUpcoming: true),
                _buildList(_past, isDark, isUpcoming: false),
              ],
            ),
    );
  }

  // ── List ──

  Widget _buildList(
    List<Map<String, dynamic>> items,
    bool isDark, {
    required bool isUpcoming,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: Brand.royalBlue,
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Column(
                children: [
                  Icon(
                    isUpcoming ? Icons.event_available : Icons.history,
                    size: 60,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isUpcoming ? 'No upcoming schedules' : 'No past schedules',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isUpcoming
                        ? 'Request a service visit to get started'
                        : 'Completed services will appear here',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
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
      color: Brand.royalBlue,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildScheduleCard(items[i], isDark),
      ),
    );
  }

  // ── Schedule Card ──

  Widget _buildScheduleCard(Map<String, dynamic> schedule, bool isDark) {
    final id = schedule['id'] as String;
    final type = schedule['schedule_type'] as String? ?? '';
    final status = schedule['status'] as String? ?? '';
    final title = schedule['title'] as String? ?? 'Service Visit';
    final dateStr = schedule['scheduled_date'] as String? ?? '';
    final time = schedule['scheduled_time'] as String?;
    final duration = schedule['estimated_duration'] as int?;
    final location = schedule['service_location'] as String?;
    final isRecurring = schedule['is_recurring'] == true;
    final isExpanded = _expandedId == id;

    final engineer = schedule['engineer'] as Map<String, dynamic>?;
    final engineerName = engineer?['full_name'] as String? ?? 'To be assigned';

    final machine = schedule['machine'] as Map<String, dynamic>?;
    final catalog = machine?['catalog'] as Map<String, dynamic>?;
    final machineName = catalog?['machine_name'] as String?;
    final serialNumber = machine?['serial_number'] as String?;

    final rating = schedule['customer_rating'] as int?;
    final isCompleted = status == 'completed';
    final canRate = isCompleted && rating == null;

    DateTime? date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {}

    // Days until
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
      } else {
        daysLabel = '${diff.abs()} days ago';
      }
    }

    return GestureDetector(
      onTap: () => setState(() => _expandedId = isExpanded ? null : id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded
                ? _typeColor(type).withAlpha(102)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: _typeColor(type).withAlpha(isDark ? 20 : 15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // ── Main Row ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _typeColor(type).withAlpha(isDark ? 38 : 26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_typeIcon(type),
                        size: 22, color: _typeColor(type)),
                  ),
                  const SizedBox(width: 14),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + recurring
                        Row(
                          children: [
                            Expanded(
                              child: Text(
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
                            ),
                            if (isRecurring)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.repeat,
                                    size: 15,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Date + Time
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 13,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight),
                            const SizedBox(width: 4),
                            Text(
                              date != null
                                  ? TimeUtils.formatDateShort(date)
                                  : dateStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.access_time,
                                  size: 13,
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight),
                              const SizedBox(width: 4),
                              Text(
                                _fmtTime(time),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Status badge + days label
                        Row(
                          children: [
                            _buildBadge(_statusLabel(status),
                                _statusColor(status), isDark),
                            if (daysLabel.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                daysLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: daysLabel == 'Today'
                                      ? const Color(0xFFF97316)
                                      : (isDark
                                          ? Brand.darkTextTertiary
                                          : Brand.subtleLight),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand arrow
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ],
              ),
            ),

            // ── Expanded Detail ──
            if (isExpanded) ...[
              Divider(
                height: 1,
                color: isDark ? Brand.darkBorder : Brand.borderLight,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status description
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withAlpha(isDark ? 20 : 15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _statusColor(status).withAlpha(51),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: _statusColor(status)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusDescription(status),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Type
                    _detailRow(
                        Icons.category, 'Type', _typeLabel(type), isDark),
                    const SizedBox(height: 10),

                    // Duration
                    if (duration != null)
                      _detailRow(
                        Icons.timelapse,
                        'Duration',
                        duration < 60
                            ? '$duration min'
                            : '${duration ~/ 60}h${duration % 60 > 0 ? ' ${duration % 60}m' : ''}',
                        isDark,
                      ),
                    if (duration != null) const SizedBox(height: 10),

                    // Time range
                    if (time != null && duration != null)
                      _detailRow(
                        Icons.schedule,
                        'Time',
                        '${_fmtTime(time)} – ${_endTimeFromDuration(time, duration)}',
                        isDark,
                      ),
                    if (time != null && duration != null)
                      const SizedBox(height: 10),

                    // Engineer
                    _detailRow(
                      Icons.engineering,
                      'Engineer',
                      engineerName,
                      isDark,
                      valueColor:
                          engineer != null ? null : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(height: 10),

                    // Machine
                    if (machineName != null) ...[
                      _detailRow(
                        Icons.precision_manufacturing,
                        'Machine',
                        '$machineName${serialNumber != null ? ' · S/N: $serialNumber' : ''}',
                        isDark,
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Location
                    if (location != null && location.isNotEmpty)
                      _detailRow(Icons.location_on_outlined, 'Location',
                          location, isDark),

                    // Description
                    if ((schedule['description'] as String?)?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        schedule['description'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.royalBlueDark,
                        ),
                      ),
                    ],

                    // Cancellation reason
                    if (status == 'cancelled' &&
                        (schedule['cancellation_reason'] as String?)
                                ?.isNotEmpty ==
                            true) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cancellation Reason',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFEF4444),
                                )),
                            const SizedBox(height: 4),
                            Text(
                              schedule['cancellation_reason'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Service report
                    if (isCompleted &&
                        (schedule['service_report'] as String?)?.isNotEmpty ==
                            true) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Brand.lightGreen.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Service Report',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Brand.lightGreenDark,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              schedule['service_report'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Rating display or Rate button
                    if (isCompleted) ...[
                      const SizedBox(height: 16),
                      if (rating != null) ...[
                        Row(
                          children: [
                            Text('Your Rating: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                )),
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < rating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 20,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                        if ((schedule['customer_feedback'] as String?)
                                ?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 4),
                          Text(
                            '"${schedule['customer_feedback']}"',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ],
                      ],
                      if (canRate)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showRatingSheet(schedule),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Rate This Service'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF59E0B),
                              side: BorderSide(
                                color: const Color(0xFFF59E0B).withAlpha(128),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isTerminal(String? status) =>
      status == 'completed' || status == 'cancelled' || status == 'rescheduled';

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 16,
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ??
                  (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
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

  Widget _buildShimmer(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}
