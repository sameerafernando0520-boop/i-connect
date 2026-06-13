// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_schedule_page.dart
// EA Schedule Calendar — Engineering Admin views all service
// schedules on a monthly calendar; tap a day to see that day's
// schedule list; tap a schedule to open its detail.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../admin/create_schedule_page.dart';
import 'ea_ticket_detail_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

// ── Status colour mapping ──────────────────────────────────────
const _statusColors = <String, Color>{
  'scheduled':   Color(0xFF3B82F6), // blue
  'confirmed':   Color(0xFF6366F1), // indigo
  'in_progress': Color(0xFFF59E0B), // amber
  'completed':   Color(0xFF16A34A), // green
  'cancelled':   Color(0xFF6B7280), // grey
  'rescheduled': Color(0xFF8B5CF6), // purple
};

const _statusLabels = <String, String>{
  'scheduled':   'Scheduled',
  'confirmed':   'Confirmed',
  'in_progress': 'In Progress',
  'completed':   'Completed',
  'cancelled':   'Cancelled',
  'rescheduled': 'Rescheduled',
};

// ── Schedule type colour mapping ───────────────────────────────
const _typeColors = <String, Color>{
  'preventive':     Color(0xFF14B8A6),
  'repair':         Color(0xFFEF4444),
  'inspection':     Color(0xFF3B82F6),
  'installation':   Color(0xFF8B5CF6),
  'warranty_visit': Color(0xFFF59E0B),
};

const _typeLabels = <String, String>{
  'preventive':     'Preventive',
  'repair':         'Repair',
  'inspection':     'Inspection',
  'installation':   'Installation',
  'warranty_visit': 'Warranty Visit',
};

// ══════════════════════════════════════════════════════════════
// Page widget
// ══════════════════════════════════════════════════════════════
class EaSchedulePage extends StatefulWidget {
  const EaSchedulePage({super.key});

  @override
  State<EaSchedulePage> createState() => _EaSchedulePageState();
}

class _EaSchedulePageState extends State<EaSchedulePage> {
  // ── Data ──
  bool _loading = true;
  String? _error;

  /// All schedules for the focused month (± 1 month buffer).
  final Map<DateTime, List<Map<String, dynamic>>> _events = {};

  // ── Calendar state ──
  CalendarFormat _calFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // ── Selected-day schedules list ──
  List<Map<String, dynamic>> _daySchedules = [];

  // ── Filter ──
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _load();
  }

  // ── Load schedules ─────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await SupabaseConfig.client
          .from('service_schedules')
          .select('''
            id,
            title,
            schedule_type,
            status,
            scheduled_date,
            scheduled_time,
            estimated_duration,
            service_location,
            ticket_id,
            customer:users!customer_id(id, full_name, phone_number),
            engineer:users!engineer_id(id, full_name)
          ''')
          .order('scheduled_date', ascending: true)
          .order('scheduled_time', ascending: true);

      final newEvents = <DateTime, List<Map<String, dynamic>>>{};
      for (final row in (rows as List)) {
        final raw = row['scheduled_date'] as String?;
        if (raw == null) continue;
        final date = _normalizeDate(DateTime.parse(raw));
        newEvents.putIfAbsent(date, () => []).add(row as Map<String, dynamic>);
      }

      if (!mounted) return;
      setState(() {
        _events.clear();
        _events.addAll(newEvents);
        _loading = false;
        _refreshDaySchedules();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Strip time component for calendar key.
  DateTime _normalizeDate(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day);

  /// Events getter for TableCalendar.
  List<Map<String, dynamic>> _getEvents(DateTime day) =>
      _events[_normalizeDate(day)] ?? [];

  void _refreshDaySchedules() {
    if (_selectedDay == null) {
      _daySchedules = [];
      return;
    }
    final all = _getEvents(_selectedDay!);
    if (_statusFilter == 'all') {
      _daySchedules = all;
    } else {
      _daySchedules = all
          .where((s) => (s['status'] as String?) == _statusFilter)
          .toList();
    }
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
      _refreshDaySchedules();
    });
  }

  void _onPageChanged(DateTime focused) {
    setState(() { _focusedDay = focused; });
  }

  // ── Helpers ───────────────────────────────────────────────
  String _formatTime(String? t) {
    if (t == null) return '';
    // t is "HH:mm:ss" from Postgres TIME
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $ampm';
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Color _statusColor(String? s) =>
      _statusColors[s ?? ''] ?? const Color(0xFF6B7280);

  String _statusLabel(String? s) =>
      _statusLabels[s ?? ''] ?? (s ?? 'Unknown');

  Color _typeColor(String? t) =>
      _typeColors[t ?? ''] ?? const Color(0xFF6B7280);

  String _typeLabel(String? t) =>
      _typeLabels[t ?? ''] ?? (t ?? '');

  // ── Navigation ────────────────────────────────────────────
  void _openDetail(Map<String, dynamic> schedule) {
    final ticketId = schedule['ticket_id'] as String?;
    if (ticketId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EaTicketDetailPage(ticketId: ticketId),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: _loading
          ? _buildShimmer(isDark)
          : _error != null
              ? _buildError(isDark)
              : RefreshIndicator(
                  color: _eaAccent,
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      _buildAppBar(isDark),
                      SliverToBoxAdapter(child: _buildCalendar(isDark)),
                      SliverToBoxAdapter(
                        child: _buildDayHeader(isDark),
                      ),
                      _daySchedules.isEmpty
                          ? SliverToBoxAdapter(
                              child: _buildEmptyDay(isDark),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, i) =>
                                      _buildScheduleCard(_daySchedules[i], isDark),
                                  childCount: _daySchedules.length,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ea_sched_fab',
        onPressed: _openCreateSchedule,
        backgroundColor: _eaAccent,
        elevation: 4,
        icon: const Icon(Icons.event_available_rounded, color: Colors.white),
        label: const Text('New Schedule',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _openCreateSchedule() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateSchedulePage()),
    );
    if (created == true) _load();
  }

  // ── AppBar ────────────────────────────────────────────────
  Widget _buildAppBar(bool isDark) {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      snap: true,
      pinned: false,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Service Schedule',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: AdminColors.text(context),
        ),
      ),
      actions: [
        // Status filter chip
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildStatusFilterButton(isDark),
        ),
        // Month total badge
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _buildMonthBadge(isDark),
        ),
      ],
    );
  }

  Widget _buildStatusFilterButton(bool isDark) {
    return PopupMenuButton<String>(
      initialValue: _statusFilter,
      onSelected: (val) {
        setState(() {
          _statusFilter = val;
          _refreshDaySchedules();
        });
      },
      icon: Icon(Icons.filter_list_rounded, color: AdminColors.textSub(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'all',        child: Text('All Statuses')),
        const PopupMenuItem(value: 'scheduled',  child: Text('Scheduled')),
        const PopupMenuItem(value: 'confirmed',  child: Text('Confirmed')),
        const PopupMenuItem(value: 'in_progress',child: Text('In Progress')),
        const PopupMenuItem(value: 'completed',  child: Text('Completed')),
        const PopupMenuItem(value: 'cancelled',  child: Text('Cancelled')),
      ],
    );
  }

  Widget _buildMonthBadge(bool isDark) {
    final monthTotal = _events.entries
        .where((e) =>
            e.key.year == _focusedDay.year &&
            e.key.month == _focusedDay.month)
        .fold<int>(0, (sum, e) => sum + e.value.length);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _eaAccent.withAlpha(isDark ? 38 : 22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _eaAccent.withAlpha(80)),
      ),
      child: Text(
        '$monthTotal this month',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _eaAccent,
        ),
      ),
    );
  }

  // ── Calendar ──────────────────────────────────────────────
  Widget _buildCalendar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: TableCalendar<Map<String, dynamic>>(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
        calendarFormat: _calFormat,
        eventLoader: _getEvents,
        startingDayOfWeek: StartingDayOfWeek.monday,
        onDaySelected: _onDaySelected,
        onFormatChanged: (fmt) => setState(() => _calFormat = fmt),
        onPageChanged: _onPageChanged,
        availableCalendarFormats: const {
          CalendarFormat.month:   'Month',
          CalendarFormat.twoWeeks: '2 Weeks',
          CalendarFormat.week:    'Week',
        },
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          formatButtonShowsNext: false,
          formatButtonDecoration: BoxDecoration(
            color: _eaAccent.withAlpha(isDark ? 45 : 28),
            borderRadius: BorderRadius.circular(12),
          ),
          formatButtonTextStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _eaAccent,
          ),
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AdminColors.text(context),
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left_rounded,
            color: AdminColors.textSub(context),
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right_rounded,
            color: AdminColors.textSub(context),
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminColors.textSub(context),
          ),
          weekendStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _eaAccent.withAlpha(180),
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(
            fontSize: 13,
            color: AdminColors.text(context),
          ),
          weekendTextStyle: TextStyle(
            fontSize: 13,
            color: _eaAccent.withAlpha(200),
          ),
          selectedDecoration: BoxDecoration(
            color: _eaAccent,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: _eaAccent.withAlpha(isDark ? 70 : 50),
            shape: BoxShape.circle,
          ),
          todayTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : _eaAccent,
          ),
          markerDecoration: const BoxDecoration(
            color: Color(0xFFF59E0B),
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
          markerSize: 5,
          markerMargin: const EdgeInsets.symmetric(horizontal: 1),
          cellMargin: const EdgeInsets.all(2),
        ),
        // Custom marker builder for multi-status dots
        calendarBuilders: CalendarBuilders(
          markerBuilder: (ctx, day, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            // Group events by status and show up to 3 coloured dots
            final statuses = events
                .map((e) => (e as Map)['status'] as String?)
                .toSet()
                .take(3)
                .toList();
            return Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: statuses.map((s) {
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: _statusColor(s),
                      shape: BoxShape.circle,
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Day header ────────────────────────────────────────────
  Widget _buildDayHeader(bool isDark) {
    final day = _selectedDay ?? _focusedDay;
    final count = _daySchedules.length;
    final allCount = _getEvents(day).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDate(day),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AdminColors.text(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _statusFilter == 'all'
                    ? '$allCount ${allCount == 1 ? 'schedule' : 'schedules'}'
                    : '$count of $allCount shown',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textHint(context),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Legend
          Wrap(
            spacing: 10,
            children: [
              _legendDot(const Color(0xFF3B82F6), 'Sched'),
              _legendDot(const Color(0xFFF59E0B), 'Active'),
              _legendDot(const Color(0xFF16A34A), 'Done'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AdminColors.textHint(context),
          ),
        ),
      ],
    );
  }

  // ── Schedule card ─────────────────────────────────────────
  Widget _buildScheduleCard(Map<String, dynamic> s, bool isDark) {
    final status = s['status'] as String?;
    final type   = s['schedule_type'] as String?;
    final title  = s['title'] as String? ?? 'Service Schedule';
    final time   = _formatTime(s['scheduled_time'] as String?);
    final dur    = s['estimated_duration'] as int?;
    final loc    = s['service_location'] as String?;

    final customer = s['customer'] as Map<String, dynamic>?;
    final engineer = s['engineer'] as Map<String, dynamic>?;
    final customerName = customer?['full_name'] as String? ?? '—';
    final engineerName = engineer?['full_name'] as String? ?? 'Unassigned';

    return GestureDetector(
      onTap: () => _openDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                    color: Colors.black.withAlpha(8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status stripe
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + status chip
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AdminColors.text(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(status, isDark),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Type chip
                      if (type != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _typeColor(type).withAlpha(isDark ? 40 : 22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _typeLabel(type),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _typeColor(type),
                            ),
                          ),
                        ),
                      // Rows
                      _infoRow(
                        Icons.access_time_rounded,
                        time.isEmpty
                            ? 'No time set'
                            : dur != null
                                ? '$time  ·  ${dur}h est.'
                                : time,
                        isDark,
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        Icons.person_outline_rounded,
                        customerName,
                        isDark,
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        Icons.engineering_rounded,
                        engineerName,
                        isDark,
                        valueColor: engineer == null
                            ? const Color(0xFFEF4444)
                            : null,
                      ),
                      if (loc != null && loc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _infoRow(
                          Icons.location_on_outlined,
                          loc,
                          isDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Chevron
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AdminColors.textHint(context),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String? status, bool isDark) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 45 : 26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, bool isDark,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 13,
          color: AdminColors.textHint(context),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? AdminColors.textSub(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Empty day ─────────────────────────────────────────────
  Widget _buildEmptyDay(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 56,
            color: AdminColors.textHint(context),
          ),
          const SizedBox(height: 14),
          Text(
            'No schedules this day',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a day with coloured dots to see its schedules.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.textHint(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer ───────────────────────────────────────────────
  Widget _buildShimmer(bool isDark) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor: isDark ? Brand.darkCard : Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Service Schedule',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AdminColors.text(context),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              _shimmerBox(isDark, height: 340, margin: 12, radius: 20),
              const SizedBox(height: 16),
              for (int i = 0; i < 3; i++)
                _shimmerBox(isDark, height: 110,
                    margin: 16, radius: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shimmerBox(bool isDark,
      {required double height,
      required double margin,
      required double radius}) {
    return Container(
      height: height,
      margin: EdgeInsets.fromLTRB(margin, 0, margin, 14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────
  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'Failed to load schedules',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.textHint(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
