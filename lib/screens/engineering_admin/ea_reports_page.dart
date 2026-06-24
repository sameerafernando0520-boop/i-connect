// lib/screens/engineering_admin/ea_reports_page.dart
// Engineering Admin Portal — Reports & Data Export

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';

const Color _eaAccent = AdminColors.success;

class EaReportsPage extends StatefulWidget {
  const EaReportsPage({super.key});

  @override
  State<EaReportsPage> createState() => _EaReportsPageState();
}

class _EaReportsPageState extends State<EaReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Date range
  _DateRange _selectedRange = _DateRange.last30;
  DateTime? _customFrom;
  DateTime? _customTo;

  // Data
  bool _loading = true;
  String? _error;

  // KPI values
  int _ticketsResolved = 0;
  int _engineersActive = 0;
  double _attendanceRate = 0.0;
  int _installationsCompleted = 0;

  // Table data
  List<Map<String, dynamic>> _ticketRows = [];
  List<Map<String, dynamic>> _attendanceRows = [];
  List<Map<String, dynamic>> _jobRows = [];

  static final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Date range helpers ────────────────────────────────────────────────────

  DateTime get _fromDate {
    if (_selectedRange == _DateRange.custom && _customFrom != null) {
      return _customFrom!;
    }
    final now = DateTime.now();
    return switch (_selectedRange) {
      _DateRange.last7   => now.subtract(const Duration(days: 7)),
      _DateRange.last30  => now.subtract(const Duration(days: 30)),
      _DateRange.last3Mo => DateTime(now.year, now.month - 3, now.day),
      _DateRange.custom  => now.subtract(const Duration(days: 30)),
    };
  }

  DateTime get _toDate {
    if (_selectedRange == _DateRange.custom && _customTo != null) {
      return _customTo!;
    }
    return DateTime.now();
  }

  String get _fromStr => _fromDate.toIso8601String().substring(0, 10);
  String get _toStr   => _toDate.toIso8601String().substring(0, 10);

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        // 1. Resolved service tickets in range
        SupabaseConfig.client
            .from('service_tickets')
            .select('id, ticket_number, title, status, created_at, resolved_at, '
                    'customer:users!user_id(full_name), '
                    'engineer:users!assigned_to(full_name)')
            .eq('ticket_type', 'support')
            .eq('is_deleted', false)
            .inFilter('status', ['resolved', 'closed', 'completed'])
            .gte('resolved_at', _fromStr)
            .lte('resolved_at', '${_toStr}T23:59:59')
            .order('resolved_at', ascending: false)
            .limit(100),

        // 2. Attendance records in range
        SupabaseConfig.client
            .from('engineer_attendance')
            .select('id, engineer_id, date, status, check_in_time, check_out_time, '
                    'engineer:users!engineer_id(full_name, employee_id)')
            .gte('date', _fromStr)
            .lte('date', _toStr)
            .order('date', ascending: false)
            .limit(200),

        // 3. Job records in range
        SupabaseConfig.client
            .from('job_records')
            .select('id, job_date, job_status, notes, '
                    'engineer:users!engineer_id(full_name, employee_id), '
                    'ticket:service_tickets!ticket_id(ticket_number, title)')
            .gte('job_date', _fromStr)
            .lte('job_date', _toStr)
            .order('job_date', ascending: false)
            .limit(200),

        // 4. Active engineers (plain list — use .length)
        SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('role', 'engineer')
            .filter('date_terminated', 'is', null),

        // 5. Installations completed in range (plain list — use .length)
        SupabaseConfig.client
            .from('machine_installations')
            .select('id')
            .eq('status', 'completed')
            .gte('updated_at', _fromStr)
            .lte('updated_at', '${_toStr}T23:59:59'),
      ]);

      if (!mounted) return;

      final tickets     = List<Map<String, dynamic>>.from(results[0] as List);
      final attendance  = List<Map<String, dynamic>>.from(results[1] as List);
      final jobs        = List<Map<String, dynamic>>.from(results[2] as List);

      // Attendance rate: present/late/half_day out of all records
      final presentStatuses = {'present', 'late', 'half_day'};
      final presentCount = attendance
          .where((r) => presentStatuses.contains(r['status']))
          .length;
      final attendanceRate = attendance.isEmpty
          ? 0.0
          : (presentCount / attendance.length) * 100;

      // Active engineers: use list length from query 4
      final activeEngineers = (results[3] as List?)?.length ?? 0;

      // Installations: use list length from query 5
      final instCount = (results[4] as List?)?.length ?? 0;

      setState(() {
        _ticketsResolved       = tickets.length;
        _engineersActive       = activeEngineers;
        _attendanceRate        = attendanceRate;
        _installationsCompleted = instCount;
        _ticketRows            = tickets;
        _attendanceRows        = attendance;
        _jobRows               = jobs;
        _loading               = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  // ── Custom date picker ────────────────────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _customFrom ?? DateTime.now().subtract(const Duration(days: 30)),
        end:   _customTo   ?? DateTime.now(),
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: _eaAccent,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customFrom = picked.start;
        _customTo   = picked.end;
        _selectedRange = _DateRange.custom;
      });
      _load();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Reports',
        accent: HeroAccent.emerald,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : _error != null
              ? _buildError(isDark)
              : _buildBody(isDark),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text('Failed to load reports',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AdminColors.text(context),
                )),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AdminColors.textHint(context))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _eaAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    return Column(
      children: [
        // Date range filters
        _buildDateFilter(isDark),
        // Tabs
        _buildTabBar(isDark),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildOverviewTab(isDark),
              _buildTicketsTab(isDark),
              _buildAttendanceTab(isDark),
            ],
          ),
        ),
      ],
    );
  }

  // ── Date filter bar ────────────────────────────────────────────────────────

  Widget _buildDateFilter(bool isDark) {
    return Container(
      color: Brand.surface(isDark),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded,
                  size: 14, color: AdminColors.textHint(context)),
              const SizedBox(width: 6),
              Text(
                '${_dateFmt.format(_fromDate)}  →  ${_dateFmt.format(_toDate)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AdminColors.textSub(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _rangeChip(_DateRange.last7,   'Last 7 days', isDark),
                const SizedBox(width: 8),
                _rangeChip(_DateRange.last30,  'Last 30 days', isDark),
                const SizedBox(width: 8),
                _rangeChip(_DateRange.last3Mo, 'Last 3 months', isDark),
                const SizedBox(width: 8),
                _customRangeChip(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(_DateRange range, String label, bool isDark) {
    final selected = _selectedRange == range;
    return GestureDetector(
      onTap: () {
        if (_selectedRange != range) {
          setState(() => _selectedRange = range);
          _load();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _eaAccent.withAlpha(26)
              : (isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: selected
                ? _eaAccent
                : (isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? _eaAccent
                : AdminColors.textSub(context),
          ),
        ),
      ),
    );
  }

  Widget _customRangeChip(bool isDark) {
    final selected = _selectedRange == _DateRange.custom;
    return GestureDetector(
      onTap: _pickCustomRange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _eaAccent.withAlpha(26)
              : (isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: selected
                ? _eaAccent
                : (isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 13,
                color: selected ? _eaAccent : AdminColors.textSub(context)),
            const SizedBox(width: 5),
            Text(
              selected && _customFrom != null
                  ? '${_dateFmt.format(_customFrom!)} – ${_dateFmt.format(_customTo!)}'
                  : 'Custom',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? _eaAccent : AdminColors.textSub(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar(bool isDark) {
    return Container(
      color: Brand.surface(isDark),
      child: Column(
        children: [
          TabBar(
            controller: _tabCtrl,
            labelColor: _eaAccent,
            unselectedLabelColor: AdminColors.textHint(context),
            indicatorColor: _eaAccent,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Tickets'),
              Tab(text: 'Attendance'),
            ],
          ),
          Container(
            height: 0.5,
            color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
          ),
        ],
      ),
    );
  }

  // ── Overview tab ──────────────────────────────────────────────────────────

  Widget _buildOverviewTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
        children: [
          // KPI cards
          Text(
            'SUMMARY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.55,
            children: [
              _KpiCard(
                isDark: isDark,
                icon: Icons.check_circle_outline_rounded,
                iconColor: _eaAccent,
                label: 'Tickets Resolved',
                value: _ticketsResolved.toString(),
              ),
              _KpiCard(
                isDark: isDark,
                icon: Icons.engineering_rounded,
                iconColor: AdminColors.info,
                label: 'Active Engineers',
                value: _engineersActive.toString(),
              ),
              _KpiCard(
                isDark: isDark,
                icon: Icons.today_rounded,
                iconColor: AdminColors.warning,
                label: 'Attendance Rate',
                value: '${_attendanceRate.toStringAsFixed(1)}%',
              ),
              _KpiCard(
                isDark: isDark,
                icon: Icons.install_desktop_rounded,
                iconColor: StatusColors.assigned,
                label: 'Installations Done',
                value: _installationsCompleted.toString(),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Job records summary
          Text(
            'JOB RECORDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 10),
          _buildJobsTable(isDark),
        ],
      ),
    );
  }

  // ── Tickets tab ───────────────────────────────────────────────────────────

  Widget _buildTicketsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _ticketRows.isEmpty
          ? _buildEmpty('No resolved tickets in this period',
              Icons.confirmation_number_outlined, isDark)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _buildTicketsTable(isDark),
              ],
            ),
    );
  }

  Widget _buildTicketsTable(bool isDark) {
    return _DataCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Text(
                  'Resolved Tickets (${_ticketRows.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          // Header
          _TableRow(
            isDark: isDark,
            isHeader: true,
            cells: const ['Ticket #', 'Title', 'Customer', 'Engineer', 'Resolved'],
            flex: const [1, 3, 2, 2, 2],
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          ...List.generate(_ticketRows.length, (i) {
            final t = _ticketRows[i];
            final resolvedAt = t['resolved_at'] as String?;
            final resolvedFmt = resolvedAt != null
                ? _dateFmt.format(DateTime.parse(resolvedAt).toLocal())
                : '—';
            final customer = (t['customer'] as Map?)?['full_name'] as String? ?? '—';
            final engineer = (t['engineer'] as Map?)?['full_name'] as String? ?? 'Unassigned';
            return Column(
              children: [
                _TableRow(
                  isDark: isDark,
                  isHeader: false,
                  cells: [
                    t['ticket_number']?.toString() ?? '—',
                    t['title'] as String? ?? '—',
                    customer,
                    engineer,
                    resolvedFmt,
                  ],
                  flex: const [1, 3, 2, 2, 2],
                ),
                if (i < _ticketRows.length - 1)
                  Container(height: 0.5,
                      margin: const EdgeInsets.only(left: 16),
                      color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Attendance tab ────────────────────────────────────────────────────────

  Widget _buildAttendanceTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: _attendanceRows.isEmpty
          ? _buildEmpty('No attendance records in this period',
              Icons.today_outlined, isDark)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _buildAttendanceSummaryCards(isDark),
                const SizedBox(height: 16),
                _buildAttendanceTable(isDark),
              ],
            ),
    );
  }

  Widget _buildAttendanceSummaryCards(bool isDark) {
    final counts = <String, int>{};
    for (final r in _attendanceRows) {
      final s = r['status'] as String? ?? 'unknown';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return Row(
      children: [
        _StatusChip(label: 'Present',  count: counts['present']  ?? 0, color: _eaAccent,                  isDark: isDark),
        const SizedBox(width: 8),
        _StatusChip(label: 'Late',     count: counts['late']     ?? 0, color: AdminColors.warning,    isDark: isDark),
        const SizedBox(width: 8),
        _StatusChip(label: 'Absent',   count: counts['absent']   ?? 0, color: AdminColors.error,          isDark: isDark),
        const SizedBox(width: 8),
        _StatusChip(label: 'Leave',    count: (counts['leave'] ?? 0) + (counts['on_leave'] ?? 0),
            color: StatusColors.assigned, isDark: isDark),
      ],
    );
  }

  Widget _buildAttendanceTable(bool isDark) {
    return _DataCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Attendance Records (${_attendanceRows.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AdminColors.text(context),
              ),
            ),
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          _TableRow(
            isDark: isDark,
            isHeader: true,
            cells: const ['Engineer', 'Emp ID', 'Date', 'Status', 'In', 'Out'],
            flex: const [3, 2, 2, 2, 2, 2],
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          ...List.generate(_attendanceRows.length, (i) {
            final r = _attendanceRows[i];
            final eng = r['engineer'] as Map?;
            final name   = eng?['full_name'] as String? ?? '—';
            final empId  = eng?['employee_id'] as String? ?? '—';
            final date   = r['date'] as String? ?? '—';
            final dateFmt = date != '—'
                ? _dateFmt.format(DateTime.parse(date))
                : '—';
            final status = r['status'] as String? ?? '—';
            final inTime  = _fmtTime(r['check_in_time'] as String?);
            final outTime = _fmtTime(r['check_out_time'] as String?);
            return Column(
              children: [
                _TableRow(
                  isDark: isDark,
                  isHeader: false,
                  cells: [name, empId, dateFmt, _capitalise(status), inTime, outTime],
                  flex: const [3, 2, 2, 2, 2, 2],
                  statusCell: 3,
                  statusColor: _statusColor(status),
                ),
                if (i < _attendanceRows.length - 1)
                  Container(height: 0.5,
                      margin: const EdgeInsets.only(left: 16),
                      color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Jobs table (Overview tab) ──────────────────────────────────────────────

  Widget _buildJobsTable(bool isDark) {
    if (_jobRows.isEmpty) {
      return _buildEmpty(
          'No job records in this period', Icons.work_outline_rounded, isDark);
    }
    return _DataCard(
      isDark: isDark,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Text(
                  'Job Records (${_jobRows.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          _TableRow(
            isDark: isDark,
            isHeader: true,
            cells: const ['Engineer', 'Date', 'Ticket', 'Status'],
            flex: const [3, 2, 3, 2],
          ),
          Container(height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          ...List.generate(_jobRows.length, (i) {
            final j = _jobRows[i];
            final eng     = j['engineer'] as Map?;
            final ticket  = j['ticket']   as Map?;
            final name    = eng?['full_name'] as String? ?? '—';
            final date    = j['job_date'] as String? ?? '—';
            final dateFmt = date != '—'
                ? _dateFmt.format(DateTime.parse(date))
                : '—';
            final ticketNum = ticket?['ticket_number']?.toString() ?? '—';
            final status    = j['job_status'] as String? ?? '—';
            return Column(
              children: [
                _TableRow(
                  isDark: isDark,
                  isHeader: false,
                  cells: [name, dateFmt, '#$ticketNum', _capitalise(status)],
                  flex: const [3, 2, 3, 2],
                  statusCell: 3,
                  statusColor: _jobStatusColor(status),
                ),
                if (i < _jobRows.length - 1)
                  Container(height: 0.5,
                      margin: const EdgeInsets.only(left: 16),
                      color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildEmpty(String msg, IconData icon, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AdminColors.textHint(context)),
          const SizedBox(height: 12),
          Text(msg,
              style: TextStyle(
                  color: AdminColors.textHint(context), fontSize: 14)),
        ],
      ),
    );
  }

  String _fmtTime(String? t) {
    if (t == null) return '—';
    try {
      final dt = DateTime.parse(t).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return t.length >= 5 ? t.substring(0, 5) : t;
    }
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }

  Color _statusColor(String s) {
    return switch (s) {
      'present'  => _eaAccent,
      'late'     => AdminColors.warning,
      'absent'   => AdminColors.error,
      'half_day' => AdminColors.info,
      _          => StatusColors.assigned,
    };
  }

  Color _jobStatusColor(String s) {
    return switch (s) {
      'completed'   => _eaAccent,
      'in_progress' => AdminColors.info,
      'pending'     => AdminColors.warning,
      _             => AdminColors.textHint(context),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date range enum
// ─────────────────────────────────────────────────────────────────────────────

enum _DateRange { last7, last30, last3Mo, custom }

// ─────────────────────────────────────────────────────────────────────────────
//  Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(
          color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(26),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Brand.darkTextPrimary : Brand.darkCard,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AdminColors.textHint(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.isDark, required this.child});
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(
          color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.isDark,
    required this.isHeader,
    required this.cells,
    required this.flex,
    this.statusCell,
    this.statusColor,
  });

  final bool isDark;
  final bool isHeader;
  final List<String> cells;
  final List<int> flex;
  final int? statusCell;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    // Minimum width so the table doesn't collapse
    const double minColW = 80;
    final totalMinW = flex.fold<double>(0, (s, f) => s + f * minColW);

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: totalMinW),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: List.generate(cells.length, (i) {
            final isStatus = i == statusCell;
            return Expanded(
              flex: flex[i],
              child: isStatus && !isHeader
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (statusColor ?? _eaAccent).withAlpha(26),
                        borderRadius: BorderRadius.circular(Brand.r(6)),
                      ),
                      child: Text(
                        cells[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor ?? _eaAccent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : Text(
                      cells[i],
                      style: TextStyle(
                        fontSize: isHeader ? 11 : 12,
                        fontWeight: isHeader
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isHeader
                            ? AdminColors.textHint(context)
                            : AdminColors.text(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            );
          }),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
    required this.isDark,
  });

  final String label;
  final int count;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
