// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_assign_engineers_sheet.dart
// EA picks engineers + lead + arrival date/time after an estimate is
// approved. Creates a service_schedule (or reuses one) and calls
// fn_dispatch_engineers RPC which atomically assigns engineers,
// posts the system chat message and fires notifications.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';

const Color _eaAccent = Color(0xFF00B4D8);

class EaAssignEngineersSheet extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic>? ticket;
  final String? currentUserId;

  const EaAssignEngineersSheet({
    super.key,
    required this.ticketId,
    required this.ticket,
    required this.currentUserId,
  });

  /// Convenience launcher — returns true if a dispatch happened.
  static Future<bool?> show(
    BuildContext context, {
    required String ticketId,
    required Map<String, dynamic>? ticket,
    required String? currentUserId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: EaAssignEngineersSheet(
            ticketId: ticketId,
            ticket: ticket,
            currentUserId: currentUserId,
          ),
        ),
      ),
    );
  }

  @override
  State<EaAssignEngineersSheet> createState() =>
      _EaAssignEngineersSheetState();
}

class _EaAssignEngineersSheetState extends State<EaAssignEngineersSheet> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  List<Map<String, dynamic>> _engineers = [];
  final Set<String> _selected = {};
  String? _leadId;

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);

  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // All active engineers; show today's attendance + active jobs to help
      // the EA pick someone realistic.
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('users')
            .select(
                'id, full_name, profile_photo, employee_id, assigned_zone, '
                'specializations, employment_type, avg_rating')
            .eq('role', 'engineer')
            .eq('is_active', true)
            .filter('date_terminated', 'is', null)
            .order('full_name'),
        SupabaseConfig.client
            .from('engineer_attendance')
            .select('engineer_id, status')
            .eq('date', today),
        SupabaseConfig.client
            .from('job_records')
            .select('engineer_id')
            .eq('job_date', today)
            .inFilter('job_status', ['pending', 'in_progress']),
      ]);

      final engs = List<Map<String, dynamic>>.from(results[0] as List);
      final att = List<Map<String, dynamic>>.from(results[1] as List);
      final jobs = List<Map<String, dynamic>>.from(results[2] as List);

      final attMap = <String, String>{};
      for (final a in att) {
        attMap[a['engineer_id'] as String] = a['status'] as String? ?? 'absent';
      }
      final jobMap = <String, int>{};
      for (final j in jobs) {
        final id = j['engineer_id'] as String;
        jobMap[id] = (jobMap[id] ?? 0) + 1;
      }

      for (final e in engs) {
        e['_att'] = attMap[e['id']] ?? 'absent';
        e['_jobs_today'] = jobMap[e['id']] ?? 0;
      }

      if (!mounted) return;
      setState(() {
        _engineers = engs;
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _dispatch() async {
    if (_selected.isEmpty || _saving) return;
    if (_leadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a lead engineer.')),
      );
      return;
    }
    if (!_selected.contains(_leadId)) {
      _selected.add(_leadId!);
    }

    setState(() => _saving = true);
    try {
      // 1) Create a service_schedules row tied to this ticket.
      final customer = widget.ticket?['customer'] as Map<String, dynamic>?;
      final customerId = customer?['id'] as String?;
      final machine = widget.ticket?['machine'] as Map<String, dynamic>?;
      final customerMachineId = machine?['id'] as String?;
      final subject =
          (widget.ticket?['subject'] as String?) ?? 'Service visit';

      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00';

      final schedRes = await SupabaseConfig.client
          .from('service_schedules')
          .insert({
            'customer_id': customerId,
            'engineer_id': _leadId, // lead used for legacy queries
            'customer_machine_id': customerMachineId,
            'ticket_id': widget.ticketId,
            'schedule_type': 'service',
            'title': subject,
            'scheduled_date': dateStr,
            'scheduled_time': timeStr,
            'status': 'scheduled',
            'created_by': widget.currentUserId,
          })
          .select('id')
          .single();

      final scheduleId = schedRes['id'] as String;

      // 2) Atomic dispatch: insert joins, post chat msg, notify everyone.
      await SupabaseConfig.client.rpc(
        'fn_dispatch_engineers',
        params: {
          'p_schedule_id': scheduleId,
          'p_engineer_ids': _selected.toList(),
          'p_lead_id': _leadId,
          'p_actor_id': widget.currentUserId,
        },
      );

      // 3) Update ticket status to in_progress
      await SupabaseConfig.client.from('service_tickets').update({
        'status': 'in_progress',
        'assigned_to': _leadId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.ticketId);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Dispatch failed: $e'),
            backgroundColor: AdminColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel = DateFormat('EEE, MMM d').format(_date);
    final timeLabel = _time.format(context);

    final filtered = _engineers.where((e) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return (e['full_name'] as String? ?? '').toLowerCase().contains(q) ||
          (e['employee_id'] as String? ?? '').toLowerCase().contains(q) ||
          (e['assigned_zone'] as String? ?? '').toLowerCase().contains(q);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AdminColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _eaAccent.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.engineering_rounded, color: _eaAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign engineers',
                        style: TextStyle(
                          color: AdminColors.text(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Pick engineers and arrival time',
                        style: TextStyle(
                          color: AdminColors.textSub(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Date + time pickers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _pickerTile(
                    context,
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: dateLabel,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pickerTile(
                    context,
                    icon: Icons.access_time_rounded,
                    label: 'Arrival',
                    value: timeLabel,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(
                  color: AdminColors.text(context), fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search engineer or zone…',
                hintStyle: TextStyle(color: AdminColors.textHint(context)),
                prefixIcon: Icon(Icons.search_rounded,
                    color: AdminColors.textSub(context)),
                filled: true,
                fillColor:
                    isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Engineer list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Error: $_error',
                              style:
                                  const TextStyle(color: Colors.redAccent)),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No engineers match.',
                              style: TextStyle(
                                  color: AdminColors.textSub(context)),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                12, 6, 12, 6),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) =>
                                _engRow(context, filtered[i], isDark),
                          ),
          ),

          // CTA
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty || _saving ? null : _dispatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _eaAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AdminColors.border(context),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _selected.isEmpty
                            ? 'Pick at least one engineer'
                            : 'Dispatch ${_selected.length} engineer${_selected.length == 1 ? "" : "s"}',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: _eaAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: AdminColors.textSub(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  Text(value,
                      style: TextStyle(
                          color: AdminColors.text(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _engRow(BuildContext context, Map<String, dynamic> e, bool isDark) {
    final id = e['id'] as String;
    final selected = _selected.contains(id);
    final isLead = _leadId == id;
    final att = e['_att'] as String? ?? 'absent';
    final jobs = e['_jobs_today'] as int? ?? 0;
    final available = att == 'present' || att == 'late' || att == 'half_day';

    return InkWell(
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(id);
          if (_leadId == id) _leadId = null;
        } else {
          _selected.add(id);
          _leadId ??= id;
        }
      }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected
              ? _eaAccent.withAlpha(20)
              : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _eaAccent.withAlpha(102)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _eaAccent.withAlpha(38),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(e['full_name'] as String? ?? '?'),
                style: const TextStyle(
                    color: _eaAccent, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            // Identity + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e['full_name'] as String? ?? 'Engineer',
                          style: TextStyle(
                              color: AdminColors.text(context),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isLead)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('LEAD',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _miniChip(
                        att,
                        available ? AdminColors.success : AdminColors.error,
                      ),
                      const SizedBox(width: 6),
                      _miniChip('$jobs today', AdminColors.info),
                      const SizedBox(width: 6),
                      if ((e['assigned_zone'] as String?)?.isNotEmpty == true)
                        _miniChip(
                          e['assigned_zone'] as String,
                          AdminColors.textSub(context),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Make-lead button (visible only when selected)
            if (selected && !isLead)
              IconButton(
                tooltip: 'Make lead',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.star_outline_rounded,
                    color: Color(0xFF8B5CF6)),
                onPressed: () => setState(() => _leadId = id),
              ),
            // Checkbox indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? _eaAccent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _eaAccent : AdminColors.border(context),
                  width: 1.4,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withAlpha(38),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );

  String _initials(String name) {
    final parts = name.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
