// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_engineer_detail_page.dart
// Engineering Admin Portal — Screen 6: Engineer Detail
// 8-tab HR profile view for an individual engineer.
// v20 — Phase 3
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';

const Color _eaAccent = Color(0xFF16A34A);

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class EaEngineerDetailPage extends StatefulWidget {
  final String engineerId;
  final String engineerName;

  const EaEngineerDetailPage({
    super.key,
    required this.engineerId,
    required this.engineerName,
  });

  @override
  State<EaEngineerDetailPage> createState() => _EaEngineerDetailPageState();
}

class _EaEngineerDetailPageState extends State<EaEngineerDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Data
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _kpis = [];
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _dispatch = [];

  bool _loading = true;
  String? _error;

  // Attendance month navigation
  DateTime _attMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Skill add sheet controllers
  final _skillNameCtrl = TextEditingController();
  String _skillLevel = 'intermediate';
  bool _skillCertified = false;
  DateTime? _certExpiry;

  static const _tabLabels = [
    'Profile',
    'Attendance',
    'Jobs',
    'Performance',
    'Skills',
    'Leave',
    'Documents',
    'Dispatch',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _skillNameCtrl.dispose();
    super.dispose();
  }

  // ── Data Loading ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _fetchProfile(),
        _fetchAttendance(),
        _fetchJobs(),
        _fetchKpi(),
        _fetchSkills(),
        _fetchLeaves(),
        _fetchDispatch(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _attendance = results[1] as List<Map<String, dynamic>>;
        _jobs = results[2] as List<Map<String, dynamic>>;
        _kpis = results[3] as List<Map<String, dynamic>>;
        _skills = results[4] as List<Map<String, dynamic>>;
        _leaves = results[5] as List<Map<String, dynamic>>;
        _dispatch = results[6] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile() async {
    return await SupabaseConfig.client
        .from('users')
        .select(
            'id, full_name, email, phone_number, profile_photo, role, '
            'employee_id, employment_type, assigned_zone, department, '
            'date_joined, created_at')
        .eq('id', widget.engineerId)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendance() async {
    final firstDay =
        DateTime(_attMonth.year, _attMonth.month, 1).toIso8601String().substring(0, 10);
    final lastDay =
        DateTime(_attMonth.year, _attMonth.month + 1, 0).toIso8601String().substring(0, 10);
    final res = await SupabaseConfig.client
        .from('engineer_attendance')
        .select(
            'id, date, status, check_in_time, check_out_time, notes')
        .eq('engineer_id', widget.engineerId)
        .gte('date', firstDay)
        .lte('date', lastDay)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchJobs() async {
    final res = await SupabaseConfig.client
        .from('job_records')
        .select(
            'id, job_date, job_status, start_time, end_time, job_type, work_done, '
            'ticket:service_tickets!ticket_id(id, ticket_number, subject, status)')
        .eq('engineer_id', widget.engineerId)
        .order('job_date', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchKpi() async {
    final res = await SupabaseConfig.client
        .from('engineer_kpi_snapshots')
        .select(
            'id, snapshot_month, completed_jobs, total_jobs, avg_rating, '
            'avg_response_time_minutes, on_time_rate, created_at')
        .eq('engineer_id', widget.engineerId)
        .order('created_at', ascending: false)
        .limit(12);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchSkills() async {
    final res = await SupabaseConfig.client
        .from('engineer_skills')
        .select(
            'id, skill_name, proficiency_level, certified, cert_expiry_date, notes')
        .eq('engineer_id', widget.engineerId)
        .order('skill_name');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _fetchLeaves() async {
    final res = await SupabaseConfig.client
        .from('engineer_leaves')
        .select(
            'id, leave_type, start_date, end_date, reason, status, '
            'reviewed_at, created_at, '
            'reviewer:users!reviewed_by(id, full_name)')
        .eq('engineer_id', widget.engineerId)
        .order('created_at', ascending: false)
        .limit(30);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Returns installations assigned to this engineer.
  Future<List<Map<String, dynamic>>> _fetchDispatch() async {
    try {
      final res = await SupabaseConfig.client
          .from('installation_engineers')
          .select(
              'id, role, status, assigned_at, acknowledged_at, '
              'installation:machine_installations!installation_id('
              '  id, title, status, scheduled_date, installation_type, '
              '  customer:users!customer_id(id, full_name)'
              ')')
          .eq('engineer_id', widget.engineerId)
          .order('assigned_at', ascending: false)
          .limit(40);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  // Reload only attendance when month changes
  Future<void> _reloadAttendance() async {
    try {
      final att = await _fetchAttendance();
      if (!mounted) return;
      setState(() => _attendance = att);
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.engineerName,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            Text(
              'Engineer Profile',
              style: TextStyle(
                fontSize: 11,
                color: AdminColors.textHint(context),
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: _eaAccent,
          unselectedLabelColor: AdminColors.textHint(context),
          indicatorColor: _eaAccent,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildProfileTab(isDark),
                    _buildAttendanceTab(isDark),
                    _buildJobsTab(isDark),
                    _buildPerformanceTab(isDark),
                    _buildSkillsTab(isDark),
                    _buildLeaveTab(isDark),
                    _buildDocumentsTab(isDark),
                    _buildDispatchTab(isDark),
                  ],
                ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  // Show FAB only for Skills (tab 4) and Leave (tab 5) via AnimatedBuilder
  Widget? _buildFab() {
    return AnimatedBuilder(
      animation: _tabs,
      builder: (_, __) {
        if (_tabs.index == 4) {
          return FloatingActionButton.extended(
            onPressed: _showAddSkillSheet,
            backgroundColor: _eaAccent,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Add Skill',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          );
        }
        if (_tabs.index == 5) {
          final pendingLeaves =
              _leaves.where((l) => l['status'] == 'pending').toList();
          if (pendingLeaves.isNotEmpty) {
            return FloatingActionButton.extended(
              onPressed: () =>
                  _showLeaveApprovalSheet(pendingLeaves.first),
              backgroundColor: AdminColors.warning,
              icon: const Icon(Icons.approval_rounded, color: Colors.white),
              label: Text(
                'Review (${pendingLeaves.length})',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            );
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  // ── Tab 1: Profile ────────────────────────────────────────────────────────

  Widget _buildProfileTab(bool isDark) {
    final p = _profile;
    if (p == null) {
      return const Center(child: Text('Profile not found'));
    }

    final name = p['full_name'] as String? ?? widget.engineerName;
    final email = p['email'] as String? ?? '';
    final phone = p['phone_number'] as String? ?? '';
    final photo = p['profile_photo'] as String?;
    final empId = p['employee_id'] as String? ?? '—';
    final empType = p['employment_type'] as String? ?? '';
    final zone = p['assigned_zone'] as String? ?? '—';
    final dept = p['department'] as String? ?? '—';
    final designation = p['department'] as String? ?? '—';
    final joinedAt = p['date_joined'] as String?;

    final textPrimary =
        isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary =
        isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header card ──
          _card(
            isDark,
            child: Row(
              children: [
                // Avatar
                _avatar(photo, name, 64, isDark),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        designation,
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _empTypeChip(empType, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Contact info ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Contact Information', isDark),
                const SizedBox(height: 12),
                _infoRow(Icons.badge_rounded, 'Employee ID', empId, isDark),
                _infoRow(Icons.email_rounded, 'Email', email.isNotEmpty ? email : '—', isDark),
                _infoRow(Icons.phone_rounded, 'Phone', phone.isNotEmpty ? phone : '—', isDark),
                _infoRow(Icons.business_rounded, 'Department', dept, isDark),
                _infoRow(Icons.location_on_rounded, 'Zone', zone, isDark),
                _infoRow(
                  Icons.calendar_today_rounded,
                  'Joined',
                  joinedAt != null
                      ? TimeUtils.formatDateFull(DateTime.tryParse(joinedAt)!)
                      : '—',
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Quick stats from KPI ──
          if (_kpis.isNotEmpty) ...[
            _sectionLabel('Latest Performance Snapshot', isDark),
            const SizedBox(height: 8),
            _buildLatestKpiCards(_kpis.first, isDark),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: Attendance ────────────────────────────────────────────────────

  Widget _buildAttendanceTab(bool isDark) {
    final textPrimary =
        isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);

    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: Column(
        children: [
          // Month navigation header
          Container(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: _eaAccent,
                  onPressed: () {
                    setState(() {
                      _attMonth = DateTime(
                          _attMonth.year, _attMonth.month - 1);
                    });
                    _reloadAttendance();
                  },
                ),
                Expanded(
                  child: Text(
                    '${_monthName(_attMonth.month)} ${_attMonth.year}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: _eaAccent,
                  onPressed: _attMonth.year == DateTime.now().year &&
                          _attMonth.month == DateTime.now().month
                      ? null
                      : () {
                          setState(() {
                            _attMonth = DateTime(
                                _attMonth.year, _attMonth.month + 1);
                          });
                          _reloadAttendance();
                        },
                ),
              ],
            ),
          ),
          // Attendance summary chips
          if (_attendance.isNotEmpty)
            _buildAttendanceSummaryRow(_attendance, isDark),
          // Attendance list
          Expanded(
            child: _attendance.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy_rounded,
                            size: 48, color: AdminColors.textHint(context)),
                        const SizedBox(height: 12),
                        Text(
                          'No records for this month',
                          style: TextStyle(
                              color: AdminColors.textHint(context)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _attendance.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _buildAttendanceRow(_attendance[i], isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryRow(
      List<Map<String, dynamic>> records, bool isDark) {
    int present = 0, absent = 0, late = 0, leave = 0;
    for (final r in records) {
      final s = r['status'] as String? ?? 'absent';
      if (s == 'present' || s == 'half_day') present++;
      if (s == 'absent') absent++;
      if (s == 'late') late++;
      if (s == 'on_leave') leave++;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryChip('Present', present, AdminColors.success, isDark),
          _summaryChip('Late', late, AdminColors.warning, isDark),
          _summaryChip('Absent', absent, AdminColors.error, isDark),
          _summaryChip('On Leave', leave, _eaAccent, isDark),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color, bool isDark) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: color),
        ),
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              color: isDark ? Brand.darkTextSecondary : const Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildAttendanceRow(Map<String, dynamic> r, bool isDark) {
    final date = r['date'] as String? ?? '';
    final status = r['status'] as String? ?? 'absent';
    final checkIn = r['check_in_time'] as String?;
    final checkOut = r['check_out_time'] as String?;

    final statusColor = _attStatusColor(status);
    final dt = DateTime.tryParse(date);
    final dateLabel = dt != null
        ? '${_dayName(dt.weekday)}, ${dt.day} ${_monthName(dt.month).substring(0, 3)}'
        : date;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (checkIn != null) ...[
                      Icon(Icons.login_rounded, size: 12,
                          color: AdminColors.textHint(context)),
                      const SizedBox(width: 3),
                      Text(
                        TimeUtils.formatTime(
                            DateTime.tryParse(checkIn) ?? DateTime.now()),
                        style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textSub(context)),
                      ),
                    ],
                    if (checkOut != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.logout_rounded, size: 12,
                          color: AdminColors.textHint(context)),
                      const SizedBox(width: 3),
                      Text(
                        TimeUtils.formatTime(
                            DateTime.tryParse(checkOut) ?? DateTime.now()),
                        style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textSub(context)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _statusBadge(_attStatusLabel(status), statusColor, isDark),
        ],
      ),
    );
  }

  // ── Tab 3: Jobs ──────────────────────────────────────────────────────────

  Widget _buildJobsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _jobs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.work_off_rounded,
                      size: 48, color: AdminColors.textHint(context)),
                  const SizedBox(height: 12),
                  Text('No job records found',
                      style:
                          TextStyle(color: AdminColors.textHint(context))),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildJobCard(_jobs[i], isDark),
            ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job, bool isDark) {
    final status = job['job_status'] as String? ?? 'pending';
    final date = job['job_date'] as String? ?? '';
    final startTime = job['start_time'] as String?;
    final endTime = job['end_time'] as String?;
    final workDone = job['work_done'] as String?;
    final ticket = job['ticket'] as Map<String, dynamic>?;
    final ticketNum = ticket?['ticket_number'] as String? ?? '';
    final ticketTitle = ticket?['subject'] as String? ?? 'Unknown Job';

    final statusColor = _jobStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticketTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF1E293B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(_jobStatusLabel(status), statusColor, isDark),
            ],
          ),
          if (ticketNum.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '#$ticketNum',
              style: TextStyle(
                  fontSize: 11,
                  color: AdminColors.textHint(context),
                  fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 12, color: AdminColors.textHint(context)),
              const SizedBox(width: 4),
              Text(
                date,
                style: TextStyle(
                    fontSize: 11, color: AdminColors.textSub(context)),
              ),
              if (startTime != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.schedule_rounded,
                    size: 12, color: AdminColors.textHint(context)),
                const SizedBox(width: 4),
                Text(
                  TimeUtils.formatTime(
                      DateTime.tryParse(startTime) ?? DateTime.now()),
                  style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSub(context)),
                ),
                if (endTime != null) ...[
                  Text(' – ', style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
                  Text(
                    TimeUtils.formatTime(
                        DateTime.tryParse(endTime) ?? DateTime.now()),
                    style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.textSub(context)),
                  ),
                ],
              ],
            ],
          ),
          if (workDone != null && workDone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              workDone,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: AdminColors.textHint(context)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 4: Performance ───────────────────────────────────────────────────

  Widget _buildPerformanceTab(bool isDark) {
    if (_kpis.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined,
                size: 48, color: AdminColors.textHint(context)),
            const SizedBox(height: 12),
            Text('No KPI data available',
                style: TextStyle(color: AdminColors.textHint(context))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _kpis.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildKpiCard(_kpis[i], isDark),
      ),
    );
  }

  Widget _buildKpiCard(Map<String, dynamic> kpi, bool isDark) {
    final period = kpi['snapshot_month'] as String? ?? '';
    final jobsCompleted = (kpi['completed_jobs'] as num?)?.toInt() ?? 0;
    final jobsAssigned = (kpi['total_jobs'] as num?)?.toInt() ?? 0;
    final avgResponse = (kpi['avg_response_time_minutes'] as num?)?.toDouble();
    final satisfaction = (kpi['avg_rating'] as num?)?.toDouble();
    final attendanceRate = (kpi['on_time_rate'] as num?)?.toDouble();

    final completionRate =
        jobsAssigned > 0 ? (jobsCompleted / jobsAssigned * 100) : 0.0;

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionLabel('SNAPSHOT: $period', isDark),
              const Spacer(),
              Icon(Icons.bar_chart_rounded,
                  color: _eaAccent, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          // Metric grid
          Row(
            children: [
              Expanded(
                  child: _kpiMetric(
                      'Jobs Done', '$jobsCompleted / $jobsAssigned',
                      AdminColors.success, isDark)),
              const SizedBox(width: 10),
              Expanded(
                  child: _kpiMetric(
                      'Completion',
                      '${completionRate.toStringAsFixed(0)}%',
                      _eaAccent,
                      isDark)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (satisfaction != null)
                Expanded(
                    child: _kpiMetric(
                        'Satisfaction',
                        '${satisfaction.toStringAsFixed(1)} ★',
                        const Color(0xFFF59E0B),
                        isDark)),
              if (attendanceRate != null) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: _kpiMetric(
                        'Attendance',
                        '${attendanceRate.toStringAsFixed(0)}%',
                        attendanceRate >= 90
                            ? AdminColors.success
                            : AdminColors.warning,
                        isDark)),
              ],
            ],
          ),
          if (avgResponse != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _kpiMetric(
                        'Avg Response',
                        '${avgResponse.toStringAsFixed(0)} min',
                        AdminColors.info,
                        isDark)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLatestKpiCards(Map<String, dynamic> kpi, bool isDark) {
    final jobsCompleted = (kpi['completed_jobs'] as num?)?.toInt() ?? 0;
    final jobsAssigned = (kpi['total_jobs'] as num?)?.toInt() ?? 0;
    final satisfaction = (kpi['avg_rating'] as num?)?.toDouble();
    final attendanceRate = (kpi['on_time_rate'] as num?)?.toDouble();

    return Row(
      children: [
        Expanded(
          child: _miniKpiTile('Jobs Done', '$jobsCompleted',
              AdminColors.success, Icons.check_circle_rounded, isDark),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniKpiTile(
              'Assigned',
              '$jobsAssigned',
              _eaAccent,
              Icons.assignment_rounded,
              isDark),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniKpiTile(
            'Rating',
            satisfaction != null
                ? satisfaction.toStringAsFixed(1)
                : '—',
            const Color(0xFFF59E0B),
            Icons.star_rounded,
            isDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniKpiTile(
            'Attendance',
            attendanceRate != null
                ? '${attendanceRate.toStringAsFixed(0)}%'
                : '—',
            attendanceRate != null && attendanceRate >= 90
                ? AdminColors.success
                : AdminColors.warning,
            Icons.calendar_month_rounded,
            isDark,
          ),
        ),
      ],
    );
  }

  Widget _miniKpiTile(
      String label, String value, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 18),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withAlpha(isDark ? 60 : 40)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AdminColors.textHint(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _kpiMetric(
      String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 5: Skills ────────────────────────────────────────────────────────

  Widget _buildSkillsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _skills.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_circle_outlined,
                      size: 48, color: AdminColors.textHint(context)),
                  const SizedBox(height: 12),
                  Text('No skills recorded',
                      style:
                          TextStyle(color: AdminColors.textHint(context))),
                  const SizedBox(height: 8),
                  Text('Tap + Add Skill to add one',
                      style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textHint(context))),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _skills.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildSkillCard(_skills[i], isDark),
            ),
    );
  }

  Widget _buildSkillCard(Map<String, dynamic> skill, bool isDark) {
    final name = skill['skill_name'] as String? ?? 'Unknown';
    final level = skill['proficiency_level'] as String? ?? 'basic';
    final certified = skill['certified'] as bool? ?? false;
    final expiry = skill['cert_expiry_date'] as String?;
    final notes = skill['notes'] as String?;

    final levelColor = _levelColor(level);
    bool isExpiringSoon = false;
    bool isExpired = false;
    if (expiry != null) {
      final expiryDate = DateTime.tryParse(expiry);
      if (expiryDate != null) {
        final now = DateTime.now();
        isExpired = expiryDate.isBefore(now);
        isExpiringSoon =
            !isExpired && expiryDate.isBefore(now.add(const Duration(days: 30)));
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpired
              ? AdminColors.error.withAlpha(100)
              : isExpiringSoon
                  ? AdminColors.warning.withAlpha(100)
                  : (isDark ? Brand.darkBorder : Brand.borderLight),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
              _statusBadge(_levelLabel(level), levelColor, isDark),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (certified) ...[
                Icon(Icons.verified_rounded,
                    size: 14, color: AdminColors.success),
                const SizedBox(width: 4),
                Text(
                  'Certified',
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (expiry != null) ...[
                Icon(
                  Icons.event_rounded,
                  size: 13,
                  color: isExpired
                      ? AdminColors.error
                      : isExpiringSoon
                          ? AdminColors.warning
                          : AdminColors.textHint(context),
                ),
                const SizedBox(width: 3),
                Text(
                  isExpired
                      ? 'Expired: $expiry'
                      : isExpiringSoon
                          ? 'Expiring: $expiry'
                          : 'Valid until: $expiry',
                  style: TextStyle(
                    fontSize: 11,
                    color: isExpired
                        ? AdminColors.error
                        : isExpiringSoon
                            ? AdminColors.warning
                            : AdminColors.textSub(context),
                    fontWeight: isExpired || isExpiringSoon
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notes,
              style: TextStyle(
                  fontSize: 11, color: AdminColors.textHint(context)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 6: Leave ─────────────────────────────────────────────────────────

  Widget _buildLeaveTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _leaves.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.beach_access_rounded,
                      size: 48, color: AdminColors.textHint(context)),
                  const SizedBox(height: 12),
                  Text('No leave applications found',
                      style:
                          TextStyle(color: AdminColors.textHint(context))),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _leaves.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildLeaveCard(_leaves[i], isDark),
            ),
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> leave, bool isDark) {
    final type = leave['leave_type'] as String? ?? 'other';
    final start = leave['start_date'] as String? ?? '';
    final end = leave['end_date'] as String? ?? '';
    final status = leave['status'] as String? ?? 'pending';
    final reason = leave['reason'] as String? ?? '';
    final reviewer = leave['reviewer'] as Map<String, dynamic>?;
    final reviewedAt = leave['reviewed_at'] as String?;

    final statusColor = _leaveStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'pending'
              ? AdminColors.warning.withAlpha(100)
              : (isDark ? Brand.darkBorder : Brand.borderLight),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _leaveTypeLabel(type),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
              _statusBadge(_leaveStatusLabel(status), statusColor, isDark),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.date_range_rounded,
                  size: 13, color: AdminColors.textHint(context)),
              const SizedBox(width: 4),
              Text(
                '$start → $end',
                style: TextStyle(
                    fontSize: 12, color: AdminColors.textSub(context)),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: TextStyle(
                  fontSize: 12, color: AdminColors.textSub(context)),
            ),
          ],
          if (reviewer != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_leaveStatusLabel(status)} by ${reviewer['full_name']}${reviewedAt != null ? ' · ${_shortDate(reviewedAt)}' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // Approve / Reject buttons for pending
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showLeaveApprovalSheet(leave),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.success,
                      side: BorderSide(
                          color: AdminColors.success.withAlpha(100)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: const Text('Approve',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _showLeaveApprovalSheet(leave, reject: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.error,
                      side: BorderSide(
                          color: AdminColors.error.withAlpha(100)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: const Text('Reject',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 7: Documents ─────────────────────────────────────────────────────

  Widget _buildDocumentsTab(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 56, color: AdminColors.textHint(context)),
          const SizedBox(height: 16),
          Text(
            'Document Vault',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Document upload coming soon',
            style: TextStyle(
                fontSize: 13, color: AdminColors.textHint(context)),
          ),
        ],
      ),
    );
  }

  // ── Tab 8: Dispatch History ───────────────────────────────────────────────

  Widget _buildDispatchTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _dispatch.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded,
                      size: 48, color: AdminColors.textHint(context)),
                  const SizedBox(height: 12),
                  Text('No dispatch offers found',
                      style:
                          TextStyle(color: AdminColors.textHint(context))),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _dispatch.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildDispatchCard(_dispatch[i], isDark),
            ),
    );
  }

  Widget _buildDispatchCard(Map<String, dynamic> offer, bool isDark) {
    final status = offer['status'] as String? ?? 'assigned';
    final assignedAt = offer['assigned_at'] as String?;
    final acknowledgedAt = offer['acknowledged_at'] as String?;
    final myRole = offer['role'] as String? ?? 'technician';
    final installation = offer['installation'] as Map<String, dynamic>?;
    final instTitle = installation?['title'] as String? ?? 'Unknown Installation';
    final instType = installation?['installation_type'] as String? ?? '';
    final customer = (installation?['customer'] as Map?)?['full_name'] as String? ?? '—';

    final statusColor = _offerStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  instTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF1E293B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(_offerStatusLabel(status), statusColor, isDark),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                customer,
                style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.textHint(context),
                    fontWeight: FontWeight.w600),
              ),
              if (instType.isNotEmpty) ...[
                Text(
                  ' · ${instType.replaceAll('_', ' ')}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textHint(context)),
                ),
              ],
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _eaAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  myRole,
                  style: const TextStyle(
                      fontSize: 11,
                      color: _eaAccent,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (assignedAt != null) ...[
                Icon(Icons.assignment_ind_rounded,
                    size: 12, color: AdminColors.textHint(context)),
                const SizedBox(width: 3),
                Text(
                  'Assigned: ${_shortDateTime(assignedAt)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSub(context)),
                ),
              ],
              if (acknowledgedAt != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_circle_outline_rounded,
                    size: 12, color: AdminColors.success),
                const SizedBox(width: 3),
                Text(
                  'Ack: ${_shortDateTime(acknowledgedAt)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSub(context)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  void _showAddSkillSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _skillNameCtrl.clear();
    _skillLevel = 'intermediate';
    _skillCertified = false;
    _certExpiry = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding:
                  const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkBorderLight
                            : Brand.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Add Skill',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Skill name
                  TextField(
                    controller: _skillNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Skill Name *',
                      filled: true,
                      fillColor: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Proficiency level
                  DropdownButtonFormField<String>(
                    value: _skillLevel,
                    items: ['basic', 'intermediate', 'advanced', 'expert']
                        .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(_levelLabel(l))))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => _skillLevel = v ?? 'intermediate'),
                    decoration: InputDecoration(
                      labelText: 'Proficiency Level',
                      filled: true,
                      fillColor: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Certified toggle
                  SwitchListTile.adaptive(
                    value: _skillCertified,
                    onChanged: (v) =>
                        setSheetState(() => _skillCertified = v),
                    title: Text(
                      'Certified',
                      style: TextStyle(
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark),
                    ),
                    activeColor: _eaAccent,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_skillCertified) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_rounded,
                          color: _eaAccent),
                      title: Text(
                        _certExpiry != null
                            ? 'Expires: ${_certExpiry!.toIso8601String().substring(0, 10)}'
                            : 'Set Cert Expiry Date',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now()
                              .add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365 * 10)),
                        );
                        if (picked != null) {
                          setSheetState(() => _certExpiry = picked);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _saveSkill(sheetCtx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _eaAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Skill',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveSkill(BuildContext sheetCtx) async {
    final name = _skillNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill name is required')),
      );
      return;
    }
    try {
      await SupabaseConfig.client.from('engineer_skills').upsert({
        'engineer_id': widget.engineerId,
        'skill_name': name,
        'proficiency_level': _skillLevel,
        'certified': _skillCertified,
        if (_certExpiry != null)
          'cert_expiry_date':
              _certExpiry!.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      Navigator.pop(sheetCtx);
      final skills = await _fetchSkills();
      if (!mounted) return;
      setState(() => _skills = skills);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showLeaveApprovalSheet(Map<String, dynamic> leave,
      {bool reject = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leaveId = leave['id'] as String;
    final type = leave['leave_type'] as String? ?? '';
    final start = leave['start_date'] as String? ?? '';
    final end = leave['end_date'] as String? ?? '';
    bool approving = !reject;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Brand.cardLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight
                          : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Review Leave Request',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_leaveTypeLabel(type)} · $start → $end',
                  style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSub(context)),
                ),
                const SizedBox(height: 20),
                // Toggle
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => approving = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: approving
                                ? AdminColors.success.withAlpha(30)
                                : (isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: approving
                                  ? AdminColors.success.withAlpha(100)
                                  : (isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '✓ Approve',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: approving
                                    ? AdminColors.success
                                    : AdminColors.textHint(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => approving = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !approving
                                ? AdminColors.error.withAlpha(30)
                                : (isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !approving
                                  ? AdminColors.error.withAlpha(100)
                                  : (isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '✗ Reject',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: !approving
                                    ? AdminColors.error
                                    : AdminColors.textHint(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        _submitLeaveDecision(leaveId, approving, sheetCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          approving ? AdminColors.success : AdminColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      approving ? 'Confirm Approval' : 'Confirm Rejection',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitLeaveDecision(
      String leaveId, bool approve, BuildContext sheetCtx) async {
    try {
      final reviewer = SupabaseConfig.client.auth.currentUser;
      await SupabaseConfig.client.from('engineer_leaves').update({
        'status': approve ? 'approved' : 'rejected',
        'reviewed_by': reviewer?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', leaveId);
      if (!mounted) return;
      Navigator.pop(sheetCtx);
      final leaves = await _fetchLeaves();
      if (!mounted) return;
      setState(() => _leaves = leaves);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Leave ${approve ? 'approved' : 'rejected'} successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ── Shared UI helpers ─────────────────────────────────────────────────────

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: child,
    );
  }

  Widget _avatar(
      String? photoUrl, String name, double size, bool isDark) {
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    final child = photoUrl != null && photoUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            width: size,
            height: size,
            placeholder: (_, __) => _avatarFallback(initials, size, isDark),
            errorWidget: (_, __, ___) =>
                _avatarFallback(initials, size, isDark),
          )
        : _avatarFallback(initials, size, isDark);

    return ClipOval(
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _avatarFallback(String initials, double size, bool isDark) {
    return Container(
      width: size,
      height: size,
      color: _eaAccent.withAlpha(isDark ? 40 : 25),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.28,
            fontWeight: FontWeight.w700,
            color: _eaAccent,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 16, color: AdminColors.textHint(context)),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSub(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Brand.darkTextPrimary
                    : const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AdminColors.textHint(context),
      ),
    );
  }

  Widget _statusBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 35 : 22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(isDark ? 70 : 50)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color),
      ),
    );
  }

  Widget _empTypeChip(String empType, bool isDark) {
    if (empType.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _eaAccent.withAlpha(isDark ? 35 : 20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _empTypeLabel(empType),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _eaAccent,
        ),
      ),
    );
  }

  // ── Label/Color helpers ───────────────────────────────────────────────────

  Color _attStatusColor(String status) {
    switch (status) {
      case 'present':
        return AdminColors.success;
      case 'late':
        return AdminColors.warning;
      case 'half_day':
        return const Color(0xFF8B5CF6);
      case 'on_leave':
        return _eaAccent;
      default:
        return AdminColors.error;
    }
  }

  String _attStatusLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'half_day':
        return 'Half Day';
      case 'on_leave':
        return 'On Leave';
      default:
        return 'Absent';
    }
  }

  Color _jobStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AdminColors.success;
      case 'in_progress':
        return _eaAccent;
      case 'cancelled':
        return AdminColors.error;
      default:
        return AdminColors.warning;
    }
  }

  String _jobStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  Color _leaveStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AdminColors.success;
      case 'rejected':
        return AdminColors.error;
      case 'cancelled':
        return AdminColors.textHint(context);
      default:
        return AdminColors.warning;
    }
  }

  String _leaveStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  String _leaveTypeLabel(String type) {
    switch (type) {
      case 'annual':
        return 'Annual Leave';
      case 'sick':
        return 'Sick Leave';
      case 'emergency':
        return 'Emergency Leave';
      case 'unpaid':
        return 'Unpaid Leave';
      default:
        return 'Other Leave';
    }
  }

  Color _offerStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AdminColors.success;
      case 'in_progress':
        return _eaAccent;
      case 'acknowledged':
        return AdminColors.info;
      case 'removed':
        return AdminColors.error;
      default:
        return AdminColors.warning; // assigned
    }
  }

  String _offerStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      case 'acknowledged':
        return 'Acknowledged';
      case 'removed':
        return 'Removed';
      default:
        return 'Assigned';
    }
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'expert':
        return const Color(0xFF8B5CF6);
      case 'advanced':
        return AdminColors.success;
      case 'intermediate':
        return _eaAccent;
      default:
        return AdminColors.warning;
    }
  }

  String _levelLabel(String level) {
    switch (level) {
      case 'expert':
        return 'Expert';
      case 'advanced':
        return 'Advanced';
      case 'intermediate':
        return 'Intermediate';
      default:
        return 'Basic';
    }
  }

  String _empTypeLabel(String type) {
    switch (type) {
      case 'full_time':
        return 'Full Time';
      case 'part_time':
        return 'Part Time';
      case 'contract':
        return 'Contract';
      default:
        return type;
    }
  }

  String _monthName(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month];
  }

  String _dayName(int weekday) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday];
  }

  String _shortDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoString.substring(0, 10);
    }
  }

  String _shortDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day}/${dt.month} $h:$m $ampm';
    } catch (_) {
      return isoString.substring(0, 16);
    }
  }
}
