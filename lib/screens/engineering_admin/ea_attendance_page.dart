// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_attendance_page.dart
// Engineering Admin Portal — Screen 7: Attendance Management
// Full-day attendance view with manual record/edit capabilities.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaAttendancePage extends StatefulWidget {
  const EaAttendancePage({super.key});

  @override
  State<EaAttendancePage> createState() => _EaAttendancePageState();
}

class _EaAttendancePageState extends State<EaAttendancePage> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _records = []; // joined with users
  String _statusFilter = 'all'; // all | present | late | absent | on_leave

  // Summary counts
  int _presentCount = 0;
  int _lateCount = 0;
  int _absentCount = 0;
  int _onLeaveCount = 0;
  int _notMarkedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. All active engineers
      final engineers = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, profile_photo, employee_id, assigned_zone, department')
          .eq('role', 'engineer')
          .filter('date_terminated', 'is', null)
          .order('full_name');

      // 2. Attendance records for selected date
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      final attendance = await SupabaseConfig.client
          .from('engineer_attendance')
          .select('*')
          .eq('date', dateStr);

      if (!mounted) return;

      // Build map: engineerId → attendance record
      final attMap = <String, Map<String, dynamic>>{};
      for (final a in attendance as List<dynamic>) {
        final rec = Map<String, dynamic>.from(a as Map);
        attMap[rec['engineer_id'] as String] = rec;
      }

      // Merge
      final merged = <Map<String, dynamic>>[];
      int present = 0, late = 0, absent = 0, onLeave = 0, notMarked = 0;

      for (final eng in engineers as List<dynamic>) {
        final e = Map<String, dynamic>.from(eng as Map);
        final att = attMap[e['id'] as String];
        final status = att?['status'] as String? ?? 'not_marked';
        e['att'] = att;
        e['att_status'] = status;
        merged.add(e);

        switch (status) {
          case 'present':
            present++;
          case 'late':
            late++;
          case 'absent':
            absent++;
          case 'on_leave':
            onLeave++;
          default:
            notMarked++;
        }
      }

      setState(() {
        _records = merged;
        _presentCount = present;
        _lateCount = late;
        _absentCount = absent;
        _onLeaveCount = onLeave;
        _notMarkedCount = notMarked;
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

  // ── Filtering ─────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _records;
    return _records
        .where((r) => r['att_status'] == _statusFilter)
        .toList();
  }

  // ── Date navigation ───────────────────────────────────────────

  void _prevDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _load();
  }

  void _nextDay() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    if (_selectedDate.isBefore(tomorrow)) {
      setState(() {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
      });
      _load();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  // ── Mark / Edit attendance ────────────────────────────────────

  Future<void> _showMarkSheet(Map<String, dynamic> eng) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final att = eng['att'] as Map<String, dynamic>?;
    final currentStatus = att?['status'] as String? ?? 'not_marked';
    String selectedStatus = currentStatus == 'not_marked' ? 'present' : currentStatus;

    TimeOfDay? checkIn = _parseTime(att?['check_in_time'] as String?);
    TimeOfDay? checkOut = _parseTime(att?['check_out_time'] as String?);
    final notesCtrl = TextEditingController(text: att?['notes'] as String? ?? '');
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final cardBg = isDark ? Brand.darkCard : Colors.white;
          final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
          final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                        color: isDark ? Brand.darkBorder : Brand.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Mark Attendance',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    eng['full_name'] as String? ?? '',
                    style: TextStyle(color: textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  // Status selector
                  Text(
                    'Status',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['present', 'late', 'absent', 'on_leave']
                        .map((s) {
                      final sel = s == selectedStatus;
                      final col = _attColor(s);
                      return ChoiceChip(
                        label: Text(_attLabel(s)),
                        selected: sel,
                        onSelected: (_) => setSheet(() => selectedStatus = s),
                        selectedColor: col.withAlpha(40),
                        backgroundColor: isDark
                            ? Brand.darkCardElevated
                            : Brand.scaffoldLight,
                        labelStyle: TextStyle(
                          color: sel ? col : textSecondary,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color: sel ? col : Colors.transparent,
                        ),
                        showCheckmark: false,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Time pickers (only for present/late)
                  if (selectedStatus == 'present' || selectedStatus == 'late') ...[
                    Row(
                      children: [
                        Expanded(
                          child: _timeTile(
                            label: 'Check In',
                            time: checkIn,
                            isDark: isDark,
                            onTap: () async {
                              final t = await showTimePicker(
                                context: sheetCtx,
                                initialTime: checkIn ?? const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (t != null) setSheet(() => checkIn = t);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _timeTile(
                            label: 'Check Out',
                            time: checkOut,
                            isDark: isDark,
                            onTap: () async {
                              final t = await showTimePicker(
                                context: sheetCtx,
                                initialTime: checkOut ?? const TimeOfDay(hour: 17, minute: 0),
                              );
                              if (t != null) setSheet(() => checkOut = t);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Notes
                  TextField(
                    controller: notesCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      labelStyle: TextStyle(color: textSecondary),
                      filled: true,
                      fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setSheet(() => saving = true);
                              await _saveAttendance(
                                engineerId: eng['id'] as String,
                                existingId: att?['id'] as String?,
                                status: selectedStatus,
                                checkIn: checkIn,
                                checkOut: checkOut,
                                notes: notesCtrl.text.trim(),
                              );
                              if (!mounted || !sheetCtx.mounted) return;
                              Navigator.pop(sheetCtx);
                              _load();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _eaAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Attendance',
                              style: TextStyle(fontWeight: FontWeight.w700),
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

  Future<void> _saveAttendance({
    required String engineerId,
    required String? existingId,
    required String status,
    required TimeOfDay? checkIn,
    required TimeOfDay? checkOut,
    required String notes,
  }) async {
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    final payload = <String, dynamic>{
      'engineer_id': engineerId,
      'date': dateStr,
      'status': status,
      'notes': notes.isEmpty ? null : notes,
      'check_in_time': checkIn != null
          ? '${checkIn.hour.toString().padLeft(2, '0')}:${checkIn.minute.toString().padLeft(2, '0')}:00'
          : null,
      'check_out_time': checkOut != null
          ? '${checkOut.hour.toString().padLeft(2, '0')}:${checkOut.minute.toString().padLeft(2, '0')}:00'
          : null,
    };


    if (existingId != null) {
      await SupabaseConfig.client
          .from('engineer_attendance')
          .update(payload)
          .eq('id', existingId);
    } else {
      await SupabaseConfig.client
          .from('engineer_attendance')
          .insert(payload);
    }
  }

  // ── Bulk mark absent ──────────────────────────────────────────

  Future<void> _bulkMarkAbsent() async {
    final notMarked = _records
        .where((r) => r['att_status'] == 'not_marked')
        .toList();
    if (notMarked.isEmpty) {
      _showSnack('No unrecorded engineers to mark absent.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All Absent'),
        content: Text(
          '${notMarked.length} engineers without records will be marked Absent for this date.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    final rows = notMarked
        .map((e) => {
              'engineer_id': e['id'],
              'date': dateStr,
              'status': 'absent',
            })
        .toList();

    await SupabaseConfig.client.from('engineer_attendance').insert(rows);
    if (!mounted) return;
    _showSnack('${notMarked.length} engineers marked absent.');
    _load();
  }

  // ── Helpers ───────────────────────────────────────────────────

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null) return null;
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '—';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return timeStr;
    }
  }

  String _attLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'on_leave':
        return 'On Leave';
      default:
        return 'Not Marked';
    }
  }

  Color _attColor(String status) {
    switch (status) {
      case 'present':
        return const Color(0xFF10B981);
      case 'late':
        return const Color(0xFFF59E0B);
      case 'absent':
        return const Color(0xFFEF4444);
      case 'on_leave':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Date label ────────────────────────────────────────────────

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (selected == today) return 'Today';
    if (selected == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${_selectedDate.day} ${months[_selectedDate.month]} ${_selectedDate.year}';
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Brand.darkBg : Brand.scaffoldLight;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        title: const Text(
          'Attendance',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          if (_notMarkedCount > 0)
            TextButton.icon(
              onPressed: _bulkMarkAbsent,
              icon: const Icon(Icons.check_box_outlined, size: 18),
              label: Text('Mark $_notMarkedCount Absent'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Date picker bar ────────────────────────────────────
          _DateBar(
            label: _dateLabel(),
            onPrev: _prevDay,
            onNext: _nextDay,
            onTap: _pickDate,
            isDark: isDark,
            canGoNext: _selectedDate.isBefore(DateTime.now()),
          ),

          // ── Summary chips ──────────────────────────────────────
          _SummaryRow(
            present: _presentCount,
            late: _lateCount,
            absent: _absentCount,
            onLeave: _onLeaveCount,
            notMarked: _notMarkedCount,
            selected: _statusFilter,
            onSelect: (s) => setState(() => _statusFilter = s),
            isDark: isDark,
          ),

          // ── List ───────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _eaAccent),
                  )
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? _EmptyState(filter: _statusFilter)
                        : RefreshIndicator(
                            color: _eaAccent,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) => _AttendanceCard(
                                eng: _filtered[i],
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                attColor: _attColor(_filtered[i]['att_status'] as String),
                                attLabel: _attLabel(_filtered[i]['att_status'] as String),
                                formatTime: _formatTime,
                                onTap: () => _showMarkSheet(_filtered[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _timeTile({
    required String label,
    required TimeOfDay? time,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: _eaAccent),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: textSecondary, fontSize: 11)),
                Text(
                  time != null
                      ? '${time.hour % 12 == 0 ? 12 : time.hour % 12}:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}'
                      : 'Tap to set',
                  style: TextStyle(
                    color: time != null ? textPrimary : textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DateBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;
  final bool isDark;
  final bool canGoNext;

  const _DateBar({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
    required this.isDark,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            color: _eaAccent,
          ),
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: _eaAccent),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down_rounded,
                    color: _eaAccent, size: 20),
              ],
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? _eaAccent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

// ── Summary Row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final int present;
  final int late;
  final int absent;
  final int onLeave;
  final int notMarked;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool isDark;

  const _SummaryRow({
    required this.present,
    required this.late,
    required this.absent,
    required this.onLeave,
    required this.notMarked,
    required this.selected,
    required this.onSelect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SummaryChip(
              label: 'All',
              count: present + late + absent + onLeave + notMarked,
              color: _eaAccent,
              selected: selected == 'all',
              onTap: () => onSelect('all'),
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              label: 'Present',
              count: present,
              color: const Color(0xFF10B981),
              selected: selected == 'present',
              onTap: () => onSelect('present'),
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              label: 'Late',
              count: late,
              color: const Color(0xFFF59E0B),
              selected: selected == 'late',
              onTap: () => onSelect('late'),
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              label: 'Absent',
              count: absent,
              color: const Color(0xFFEF4444),
              selected: selected == 'absent',
              onTap: () => onSelect('absent'),
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              label: 'On Leave',
              count: onLeave,
              color: const Color(0xFF8B5CF6),
              selected: selected == 'on_leave',
              onTap: () => onSelect('on_leave'),
            ),
            if (notMarked > 0) ...[
              const SizedBox(width: 8),
              _SummaryChip(
                label: 'Not Marked',
                count: notMarked,
                color: const Color(0xFF94A3B8),
                selected: selected == 'not_marked',
                onTap: () => onSelect('not_marked'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withAlpha(60),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attendance Card ───────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> eng;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color attColor;
  final String attLabel;
  final String Function(String?) formatTime;
  final VoidCallback onTap;

  const _AttendanceCard({
    required this.eng,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.attColor,
    required this.attLabel,
    required this.formatTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final att = eng['att'] as Map<String, dynamic>?;
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;
    final photoUrl = eng['profile_photo'] as String?;
    final name = eng['full_name'] as String? ?? 'Unknown';
    final empId = eng['employee_id'] as String? ?? '';
    final zone = eng['assigned_zone'] as String? ?? '';
    final designation = eng['department'] as String? ?? '';
    final checkIn = att?['check_in_time'] as String?;
    final checkOut = att?['check_out_time'] as String?;
    final notes = att?['notes'] as String?;

    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: attColor, width: 4),
          top: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: attColor.withAlpha(80),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _AvatarFallback(
                              initials: initials,
                              isDark: isDark,
                            ),
                            errorWidget: (_, __, ___) => _AvatarFallback(
                              initials: initials,
                              isDark: isDark,
                            ),
                          )
                        : _AvatarFallback(initials: initials, isDark: isDark),
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: attColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: attColor.withAlpha(60)),
                            ),
                            child: Text(
                              attLabel,
                              style: TextStyle(
                                color: attColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        designation.isNotEmpty ? '$designation · $empId' : empId,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (zone.isNotEmpty)
                        Text(
                          'Zone: $zone',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      // Times
                      if (checkIn != null || checkOut != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (checkIn != null) ...[
                              Icon(Icons.login_rounded,
                                  size: 12,
                                  color: const Color(0xFF10B981)),
                              const SizedBox(width: 3),
                              Text(
                                formatTime(checkIn),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (checkOut != null) ...[
                              Icon(Icons.logout_rounded,
                                  size: 12,
                                  color: const Color(0xFFEF4444)),
                              const SizedBox(width: 3),
                              Text(
                                formatTime(checkOut),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          notes,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit_rounded, size: 16, color: _eaAccent.withAlpha(160)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String initials;
  final bool isDark;

  const _AvatarFallback({required this.initials, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Brand.royalBlue,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

// ── Error / Empty ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'Failed to load attendance',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Brand.darkTextPrimary
                    : const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = filter == 'all'
        ? 'No engineers found'
        : 'No engineers with "${filter.replaceAll('_', ' ')}" status';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: isDark ? Brand.darkTextSecondary : const Color(0xFF64748B),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
