import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/admin/shimmer_loading.dart';
import 'create_schedule_page.dart';
import 'schedule_detail_page.dart';

// ── Schedule Type Helpers ──

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

String _formatScheduleTime(String? timeStr) {
  if (timeStr == null || timeStr.isEmpty) return '';
  final parts = timeStr.split(':');
  if (parts.length < 2) return timeStr;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  final period = hour >= 12 ? 'PM' : 'AM';
  final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  return '$h:${minute.toString().padLeft(2, '0')} $period';
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

class ServiceCalendarPage extends StatefulWidget {
  const ServiceCalendarPage({super.key});

  @override
  State<ServiceCalendarPage> createState() => _ServiceCalendarPageState();
}

class _ServiceCalendarPageState extends State<ServiceCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  List<Map<String, dynamic>> _selectedDaySchedules = [];
  bool _loading = true;
  bool _hasError = false;
  String _typeFilter = 'all';

  // Summary counts for the current view
  int _totalToday = 0;
  int _totalPending = 0;

  static const _typeFilters = [
    'all',
    'preventive',
    'repair',
    'inspection',
    'installation',
    'warranty_visit',
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  DateTime _normalizeDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Data Loading ──

  Future<void> _loadSchedules() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final firstDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
      final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 2, 0);

      final data = await SupabaseConfig.client
          .from('service_schedules')
          .select('''
            id, title, description, schedule_type, status,
            scheduled_date, scheduled_time, estimated_duration,
            service_location, is_recurring,
            customer_id, engineer_id,
            customer:users!customer_id(id, full_name, profile_photo, company_name),
            engineer:users!engineer_id(id, full_name, profile_photo)
          ''')
          .gte('scheduled_date', _fmtDate(firstDay))
          .lte('scheduled_date', _fmtDate(lastDay))
          .order('scheduled_date')
          .order('scheduled_time');

      if (!mounted) return;

      final schedules = List<Map<String, dynamic>>.from(data);
      final Map<DateTime, List<Map<String, dynamic>>> events = {};
      int todayCount = 0;
      int pendingCount = 0;
      final todayKey = _normalizeDate(DateTime.now());

      for (final s in schedules) {
        final dateStr = s['scheduled_date'] as String? ?? '';
        if (dateStr.isEmpty) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final key = _normalizeDate(date);
        events.putIfAbsent(key, () => []);
        events[key]!.add(s);

        if (key == todayKey) todayCount++;
        final status = s['status'] as String? ?? '';
        if (status == 'requested' || status == 'scheduled') pendingCount++;
      }

      setState(() {
        _events = events;
        _loading = false;
        _totalToday = todayCount;
        _totalPending = pendingCount;
      });
      _updateSelectedDaySchedules();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.error_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Failed to load schedules')),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.error,
        ),
      );
    }
  }

  void _updateSelectedDaySchedules() {
    final key = _normalizeDate(_selectedDay);
    final dayEvents = _events[key] ?? [];

    final filtered = _typeFilter == 'all'
        ? List<Map<String, dynamic>>.from(dayEvents)
        : dayEvents
            .where((s) => s['schedule_type'] == _typeFilter)
            .toList();

    setState(() => _selectedDaySchedules = filtered);
  }

  Future<void> _navigateToCreate() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateSchedulePage()),
    );
    if (!mounted) return;
    if (result == true) _loadSchedules();
  }

  Future<void> _navigateToDetail(String scheduleId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleDetailPage(scheduleId: scheduleId),
      ),
    );
    if (!mounted) return;
    _loadSchedules();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom Header ──
            _buildTopHeader(isDark),
            // ── Body ──
            Expanded(
              child: _loading
                  ? _buildShimmer(isDark)
                  : _hasError
                      ? _buildErrorState(isDark)
                      : RefreshIndicator(
                          color: Brand.royalBlue,
                          onRefresh: _loadSchedules,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    // ── Summary Bar ──
                                    if (_totalToday > 0 || _totalPending > 0)
                                      _buildSummaryBar(isDark),

                                    // ── Calendar ──
                                    _buildCalendar(isDark),

                                    // ── Type Filters ──
                                    _buildTypeFilters(isDark),

                                    // ── Selected Day Header ──
                                    _buildDayHeader(isDark),
                                  ],
                                ),
                              ),

                              // ── Schedule List ──
                              _selectedDaySchedules.isEmpty
                                  ? SliverFillRemaining(
                                      child: _buildEmptyDay(isDark),
                                    )
                                  : SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 100),
                                      sliver: SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (_, i) {
                                            final isLast = i ==
                                                _selectedDaySchedules.length - 1;
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: isLast ? 0 : 10,
                                              ),
                                              child: _buildScheduleCard(
                                                _selectedDaySchedules[i],
                                                isDark,
                                              ),
                                    );
                                  },
                                  childCount: _selectedDaySchedules.length,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP HEADER ────────────────────────────────────────
  Widget _buildTopHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Brand.darkIconActive : AdminColors.primary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service Calendar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
                  ),
                ),
                Text(
                  '$_totalToday scheduled today',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
              _loadSchedules();
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(
                Icons.today_rounded,
                color: isDark ? Brand.darkIconActive : AdminColors.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _navigateToCreate,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AdminColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AdminColors.primary.withAlpha(89),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary Bar ──

  Widget _buildSummaryBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          if (_totalToday > 0)
            Expanded(
              child: _buildSummaryChip(
                icon: Icons.today,
                label: 'Today',
                value: '$_totalToday',
                color: Brand.royalBlue,
                isDark: isDark,
              ),
            ),
          if (_totalToday > 0 && _totalPending > 0) const SizedBox(width: 8),
          if (_totalPending > 0)
            Expanded(
              child: _buildSummaryChip(
                icon: Icons.pending_actions,
                label: 'Pending',
                value: '$_totalPending',
                color: AdminColors.warning,
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Brand.darkTextSecondary : AdminColors.textSub(context),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Calendar Widget ──

  Widget _buildCalendar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: TableCalendar<Map<String, dynamic>>(
        firstDay: DateTime.utc(2023, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        calendarFormat: _calendarFormat,
        startingDayOfWeek: StartingDayOfWeek.monday,
        eventLoader: (day) {
          final key = _normalizeDate(day);
          return _events[key] ?? [];
        },
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
          _updateSelectedDaySchedules();
        },
        onFormatChanged: (format) {
          setState(() => _calendarFormat = format);
        },
        onPageChanged: (focused) {
          // Use setState so header re-renders with new month
          setState(() => _focusedDay = focused);
          _loadSchedules();
        },
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          formatButtonShowsNext: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
          ),
          formatButtonDecoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          formatButtonTextStyle: TextStyle(
            color: isDark
                ? Brand.darkTextSecondary
                : AdminColors.textSub(context),
            fontSize: 12,
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left,
            color: isDark
                ? Brand.darkTextSecondary
                : AdminColors.textSub(context),
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right,
            color: isDark
                ? Brand.darkTextSecondary
                : AdminColors.textSub(context),
          ),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Brand.darkTextSecondary
                : AdminColors.textSub(context),
          ),
          weekendStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Brand.darkTextTertiary
                : AdminColors.textHint(context),
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: Brand.royalBlueLight.withAlpha(51),
            shape: BoxShape.circle,
          ),
          todayTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
          ),
          selectedDecoration: const BoxDecoration(
            color: Brand.royalBlue,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          defaultTextStyle: TextStyle(
            color: isDark
                ? Brand.darkTextPrimary
                : AdminColors.text(context),
          ),
          weekendTextStyle: TextStyle(
            color: isDark
                ? Brand.darkTextSecondary
                : AdminColors.textSub(context),
          ),
          // markerDecoration is overridden by calendarBuilders
          // but kept as fallback
          markersMaxCount: 4,
          markersAlignment: Alignment.bottomCenter,
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (ctx, date, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            final count = events.length.clamp(1, 4);
            return Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(count, (i) {
                  final type =
                      (events[i] as Map)['schedule_type'] as String?;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _typeColor(type),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Type Filters ──

  Widget _buildTypeFilters(bool isDark) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _typeFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final type = _typeFilters[i];
          final selected = _typeFilter == type;
          final color = type == 'all' ? Brand.royalBlue : _typeColor(type);

          // Count events of this type for all days
          int count = 0;
          if (type != 'all') {
            for (final events in _events.values) {
              count += events
                  .where((s) => s['schedule_type'] == type)
                  .length;
            }
          }

          return FilterChip(
            key: ValueKey(type),
            label: Text(
              type == 'all'
                  ? 'All'
                  : (count > 0
                      ? '${_typeLabel(type)} ($count)'
                      : _typeLabel(type)),
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? Colors.white
                    : (isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSub(context)),
              ),
            ),
            selected: selected,
            onSelected: (_) {
              setState(() => _typeFilter = type);
              _updateSelectedDaySchedules();
            },
            selectedColor: color,
            backgroundColor:
                isDark ? Brand.darkCard : Colors.white,
            side: BorderSide(
              color: selected
                  ? color
                  : (isDark
                      ? Brand.darkBorder
                      : Brand.borderLight),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  // ── Selected Day Header ──

  Widget _buildDayHeader(bool isDark) {
    final isToday = isSameDay(_selectedDay, DateTime.now());
    final count = _selectedDaySchedules.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? 'Today'
                      : TimeUtils.formatDateFull(_selectedDay),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : AdminColors.text(context),
                  ),
                ),
                if (!isToday)
                  Text(
                    TimeUtils.formatDateFull(_selectedDay),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Brand.darkTextTertiary
                          : AdminColors.textHint(context),
                    ),
                  ),
              ],
            ),
          ),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(26),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count ${count == 1 ? 'schedule' : 'schedules'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Brand.royalBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Empty Day ──

  Widget _buildEmptyDay(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available,
            size: 56,
            color: isDark
                ? Brand.darkTextTertiary
                : AdminColors.textHint(context),
          ),
          const SizedBox(height: 12),
          Text(
            'No schedules for this day',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _typeFilter != 'all'
                ? 'No "${_typeLabel(_typeFilter)}" schedules'
                : 'Tap + to add a schedule',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _navigateToCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Schedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.royalBlue,
              side: const BorderSide(color: Brand.royalBlue),
            ),
          ),
        ],
      ),
    );
  }

  // ── Schedule Card ──

  Widget _buildScheduleCard(
      Map<String, dynamic> schedule, bool isDark) {
    final type = schedule['schedule_type'] as String? ?? '';
    final status = schedule['status'] as String? ?? '';
    final title = schedule['title'] as String? ?? 'Untitled';
    final time = schedule['scheduled_time'] as String?;
    final duration = schedule['estimated_duration'] as int?;
    final location = schedule['service_location'] as String?;
    final isRecurring = schedule['is_recurring'] == true;

    final customer = schedule['customer'] as Map<String, dynamic>?;
    final engineer = schedule['engineer'] as Map<String, dynamic>?;

    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final companyName = customer?['company_name'] as String? ?? '';
    final engineerName =
        engineer?['full_name'] as String? ?? 'Unassigned';

    return GestureDetector(
      onTap: () => _navigateToDetail(schedule['id'] as String),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // ── Color Bar ──
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

              // ── Content ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Row: Time + Badges ──
                      Row(
                        children: [
                          if (time != null &&
                              time.isNotEmpty) ...[
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : AdminColors.textHint(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              duration != null
                                  ? '${_formatScheduleTime(time)} – ${_endTimeFromDuration(time, duration)}'
                                  : _formatScheduleTime(time),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : AdminColors.textSub(context),
                              ),
                            ),
                          ],
                          const Spacer(),
                          _buildBadge(
                            _typeLabel(type),
                            _typeColor(type),
                            isDark,
                          ),
                          const SizedBox(width: 6),
                          _buildBadge(
                            _statusLabel(status),
                            _statusColor(status),
                            isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Title ──
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
                                    : AdminColors.text(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRecurring)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Tooltip(
                                message: 'Recurring',
                                child: Icon(
                                  Icons.repeat,
                                  size: 16,
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : AdminColors.textHint(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Location ──
                      if (location != null &&
                          location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : AdminColors.textHint(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : AdminColors.textHint(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Divider ──
                      Divider(
                        height: 12,
                        color: isDark
                            ? Brand.darkBorder
                            : Brand.borderLight,
                      ),

                      // ── Customer + Engineer ──
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : AdminColors.textHint(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              companyName.isNotEmpty
                                  ? '$customerName · $companyName'
                                  : customerName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : AdminColors.textSub(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.engineering_outlined,
                            size: 14,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : AdminColors.textHint(context),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              engineerName,
                              style: TextStyle(
                                fontSize: 12,
                                color: engineer != null
                                    ? (isDark
                                        ? Brand.darkTextSecondary
                                        : AdminColors.textSub(context))
                                    : AdminColors.warning,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Chevron ──
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context),
                ),
              ),
            ],
          ),
        ),
      ),
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── Error State ──

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: isDark
                ? Brand.darkTextTertiary
                : AdminColors.textHint(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load schedules',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadSchedules,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.royalBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer ──

  Widget _buildShimmer(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const ShimmerLoading(
          child: SkeletonBox(
            width: double.infinity,
            height: 320,
            radius: 16,
          ),
        ),
        const SizedBox(height: 12),
        // Filter chips shimmer
        Row(
          children: List.generate(
            4,
            (_) => const Padding(
              padding: EdgeInsets.only(right: 8),
              child: ShimmerLoading(
                child: SkeletonBox(width: 80, height: 32, radius: 20),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Schedule cards shimmer
        ...List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerLoading(
              child: SkeletonBox(
                width: double.infinity,
                height: 110,
                radius: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}