// lib/screens/admin/admin_installation_detail_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const _typeLabels = {
  'new_install':   'New Install',
  'replacement':   'Replacement',
  'upgrade':       'Upgrade',
  'commissioning': 'Commissioning',
  'decommission':  'Decommission',
};

const _typeColors = {
  'new_install':   Color(0xFF10B981),
  'replacement':   Color(0xFF3B82F6),
  'upgrade':       Color(0xFF8B5CF6),
  'commissioning': Color(0xFFF59E0B),
  'decommission':  Color(0xFFEF4444),
};

const _statusColors = {
  'pending':     Color(0xFFF59E0B),
  'scheduled':   Color(0xFF3B82F6),
  'in_progress': Color(0xFF8B5CF6),
  'completed':   Color(0xFF10B981),
  'cancelled':   Color(0xFF6B7280),
};

// ══════════════════════════════════════════════════════════════
//  ADMIN INSTALLATION DETAIL PAGE
// ══════════════════════════════════════════════════════════════
class AdminInstallationDetailPage extends StatefulWidget {
  final String installationId;
  const AdminInstallationDetailPage(
      {super.key, required this.installationId});

  @override
  State<AdminInstallationDetailPage> createState() =>
      _AdminInstallationDetailPageState();
}

class _AdminInstallationDetailPageState
    extends State<AdminInstallationDetailPage> {
  bool _isLoading = true;
  String? _error;
  bool _changed = false;
  Map<String, dynamic> _install = {};
  List<Map<String, dynamic>> _engineers = []; // assigned engineers

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await SupabaseConfig.client
          .from('machine_installations')
          .select('''
            *,
            customer:users!customer_id(id, full_name, phone_number),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number, image_url)
            ),
            installation_engineers(
              id, role, status, assigned_at, acknowledged_at,
              engineer:users!engineer_id(
                id, full_name, profile_photo, employee_id, phone_number, assigned_zone
              )
            )
          ''')
          .eq('id', widget.installationId)
          .single();
      if (!mounted) return;
      setState(() {
        _install = Map<String, dynamic>.from(data as Map);
        _engineers = List<Map<String, dynamic>>.from(
          (data['installation_engineers'] as List?) ?? [],
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Status update ─────────────────────────────────────────────
  Future<void> _updateStatus(String newStatus) async {
    String? report;

    if (newStatus == 'completed') {
      final ctrl = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Mark as Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a completion report (optional):',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Summary of work done...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      report = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
      ctrl.dispose();
      if (confirmed != true) return;
    } else if (newStatus == 'cancelled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cancel Installation'),
          content: const Text(
              'Are you sure you want to cancel this installation?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('No')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.error),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Cancel Installation',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await SupabaseConfig.client.rpc('update_installation_status', params: {
        'p_installation_id': widget.installationId,
        'p_status': newStatus,
        if (report != null) 'p_completion_report': report,
      });
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error),
      );
    }
  }

  // ── Assign engineers ──────────────────────────────────────────
  Future<void> _showAssignSheet() async {
    List<Map<String, dynamic>> allEngineers = [];
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select(
              'id, full_name, profile_photo, employee_id, assigned_zone, phone_number')
          .eq('role', 'engineer')
          .order('full_name');
      allEngineers =
          List<Map<String, dynamic>>.from(data as List);
    } catch (_) {}

    if (!mounted) return;

    // Pre-select already assigned (non-removed) engineers
    final assignedIds = _engineers
        .where((e) => e['status'] != 'removed')
        .map((e) =>
            (e['engineer'] as Map?)?['id'] as String? ?? '')
        .toSet();

    final Map<String, String> selectedRoles = {};
    for (final e in _engineers.where((e) => e['status'] != 'removed')) {
      final engMap = e['engineer'] as Map<dynamic, dynamic>?;
      final engId = engMap?['id'] as String? ?? '';
      selectedRoles[engId] = e['role'] as String? ?? 'technician';
    }
    final Set<String> selectedIds = Set.from(assignedIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSt) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, ctrl) => Container(
            decoration: BoxDecoration(
              color: AdminColors.card(sheetCtx),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AdminColors.border(sheetCtx),
                        borderRadius: BorderRadius.circular(Brand.r(2)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    children: [
                      Text('Assign Engineers',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.text(sheetCtx))),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: allEngineers.length,
                    itemBuilder: (_, i) {
                      final eng = allEngineers[i];
                      final id = eng['id'] as String;
                      final isSelected = selectedIds.contains(id);
                      final role = selectedRoles[id] ?? 'technician';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AdminColors.primary.withAlpha(20)
                              : AdminColors.bg(sheetCtx),
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          border: Border.all(
                            color: isSelected
                                ? AdminColors.primary
                                : AdminColors.border(sheetCtx),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor:
                                    AdminColors.primary.withAlpha(40),
                                backgroundImage: eng['profile_photo'] != null
                                    ? NetworkImage(
                                        eng['profile_photo'] as String)
                                    : null,
                                child: eng['profile_photo'] == null
                                    ? Text(
                                        (eng['full_name'] as String? ??
                                                '?')[0]
                                            .toUpperCase(),
                                        style: TextStyle(
                                            color: AdminColors.primary,
                                            fontWeight: FontWeight.w700))
                                    : null,
                              ),
                              title: Text(
                                  eng['full_name'] as String? ?? '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                '${eng['employee_id'] ?? '—'} • ${eng['assigned_zone'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AdminColors.textSub(
                                        sheetCtx)),
                              ),
                              trailing: Checkbox(
                                value: isSelected,
                                activeColor: AdminColors.primary,
                                onChanged: (v) => setSt(() {
                                  if (v == true) {
                                    selectedIds.add(id);
                                    selectedRoles[id] = 'technician';
                                  } else {
                                    selectedIds.remove(id);
                                    selectedRoles.remove(id);
                                  }
                                }),
                              ),
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 10),
                                child: Row(
                                  children: [
                                    Text('Role: ',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AdminColors.textSub(
                                                sheetCtx))),
                                    for (final r in [
                                      'lead',
                                      'technician',
                                      'assistant'
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            right: 6),
                                        child: ChoiceChip(
                                          label: Text(
                                              _capitalize(r),
                                              style:
                                                  const TextStyle(
                                                      fontSize: 11)),
                                          selected: role == r,
                                          selectedColor:
                                              AdminColors.primary,
                                          labelStyle: TextStyle(
                                              color: role == r
                                                  ? Colors.white
                                                  : AdminColors.text(
                                                      sheetCtx)),
                                          onSelected: (_) => setSt(() =>
                                              selectedRoles[id] = r),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      12 +
                          MediaQuery.of(sheetCtx).viewInsets.bottom),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(12))),
                    ),
                    onPressed: () async {
                      if (selectedIds.isEmpty) {
                        Navigator.pop(sheetCtx);
                        return;
                      }
                      final payload = selectedIds
                          .map((id) => {
                                'engineer_id': id,
                                'role': selectedRoles[id] ??
                                    'technician',
                              })
                          .toList();
                      try {
                        await SupabaseConfig.client.rpc(
                          'assign_installation_engineers',
                          params: {
                            'p_installation_id':
                                widget.installationId,
                            'p_engineers': payload,
                          },
                        );
                        if (!sheetCtx.mounted) return;
                        Navigator.pop(sheetCtx);
                        _changed = true;
                        _load();
                      } catch (e) {
                        if (!sheetCtx.mounted) return;
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AdminColors.error),
                        );
                      }
                    },
                    child: Text(
                      'Save (${selectedIds.length} selected)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Remove engineer ───────────────────────────────────────────
  Future<void> _removeEngineer(String engineerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove Engineer'),
        content:
            const Text('Remove this engineer from the installation?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text('Remove',
                  style:
                      TextStyle(color: AdminColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseConfig.client.rpc(
        'remove_installation_engineer',
        params: {
          'p_installation_id': widget.installationId,
          'p_engineer_id': engineerId,
        },
      );
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────
  String _fmtDate(String? s) {
    if (s == null) return '—';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  String _fmtDateTime(String? s) {
    if (s == null) return '—';
    try {
      return DateFormat('dd MMM yyyy, HH:mm')
          .format(DateTime.parse(s).toLocal());
    } catch (_) {
      return s;
    }
  }

  String _fmtStatus(String s) => switch (s) {
        'in_progress' => 'In Progress',
        'pending' => 'Pending',
        'scheduled' => 'Scheduled',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _changed) {
          // signal refresh to caller handled by Navigator.pop return value
        }
      },
      child: Scaffold(
        backgroundColor: AdminColors.bg(context),
        appBar: DsPageHeader(
          title: 'Installation Detail',
          accent: HeroAccent.navy,
          onBack: () => Navigator.pop(context, _changed),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AdminColors.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: AdminColors.text(context))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _load,
                            child: const Text('Retry')),
                      ],
                    ),
                  )
                : _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final status = _install['status'] as String? ?? 'pending';
    final type =
        _install['installation_type'] as String? ?? 'new_install';
    final customer = _install['customer'] as Map? ?? {};
    final machine = _install['machine'] as Map? ?? {};
    final catalog = machine['catalog'] as Map? ?? {};
    final statusColor = _statusColors[status] ?? Colors.grey;
    final typeColor = _typeColors[type] ?? Colors.grey;
    final activeEngineers = _engineers
        .where((e) => e['status'] != 'removed')
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Status header card ──
          _card(context: context, isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(_typeLabels[type] ?? type, typeColor),
                  const SizedBox(width: 8),
                  _badge(_fmtStatus(status), statusColor),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _install['title'] as String? ?? '(Untitled)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context)),
              ),
              if (_install['description'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  _install['description'] as String,
                  style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSub(context)),
                ),
              ],
            ],
          )),
          const SizedBox(height: 12),

          // ── Status action buttons ──
          if (status != 'completed' && status != 'cancelled')
            _card(context: context, isDark: isDark, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update Status',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textSub(context))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status == 'scheduled')
                      _actionBtn('Mark In Progress',
                          const Color(0xFF8B5CF6), Icons.play_arrow,
                          () => _updateStatus('in_progress')),
                    if (status == 'in_progress')
                      _actionBtn('Mark Completed',
                          const Color(0xFF10B981), Icons.check_circle,
                          () => _updateStatus('completed')),
                    _actionBtn('Cancel Installation',
                        AdminColors.error, Icons.cancel,
                        () => _updateStatus('cancelled')),
                  ],
                ),
              ],
            )),
          if (status != 'completed' && status != 'cancelled')
            const SizedBox(height: 12),

          // ── Customer & Machine ──
          _card(context: context, isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Machine & Customer', context),
              const SizedBox(height: 12),
              _row(Icons.precision_manufacturing_outlined,
                  '${catalog['machine_name'] ?? '—'} (${catalog['model_number'] ?? ''})',
                  context),
              const SizedBox(height: 6),
              _row(Icons.confirmation_number_outlined,
                  'SN: ${machine['serial_number'] ?? '—'}', context),
              const SizedBox(height: 6),
              _row(Icons.person_outline,
                  customer['full_name'] as String? ?? '—', context),
              if (customer['phone_number'] != null) ...[
                const SizedBox(height: 6),
                _row(Icons.phone_outlined,
                    customer['phone_number'] as String, context),
              ],
            ],
          )),
          const SizedBox(height: 12),

          // ── Schedule ──
          _card(context: context, isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Schedule & Location', context),
              const SizedBox(height: 12),
              _row(Icons.calendar_today,
                  _fmtDate(_install['scheduled_date'] as String?),
                  context),
              if (_install['scheduled_time'] != null) ...[
                const SizedBox(height: 6),
                _row(Icons.access_time,
                    _install['scheduled_time'] as String, context),
              ],
              if (_install['estimated_duration_hours'] != null) ...[
                const SizedBox(height: 6),
                _row(Icons.timer_outlined,
                    '${_install['estimated_duration_hours']} hours estimated',
                    context),
              ],
              if (_install['location'] != null) ...[
                const SizedBox(height: 6),
                _row(Icons.location_on_outlined,
                    _install['location'] as String, context),
              ],
            ],
          )),
          const SizedBox(height: 12),

          // ── Engineers ──
          _card(context: context, isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _sectionTitle('Assigned Engineers', context),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showAssignSheet,
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('Assign'),
                    style: TextButton.styleFrom(
                        foregroundColor: AdminColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (activeEngineers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No engineers assigned yet.',
                      style: TextStyle(
                          color: AdminColors.textSub(context),
                          fontSize: 13)),
                )
              else
                ...activeEngineers.map((e) {
                  final eng = e['engineer'] as Map? ?? {};
                  final engId = eng['id'] as String? ?? '';
                  final roleStr =
                      e['role'] as String? ?? 'technician';
                  final engStatus = e['status'] as String? ?? '';
                  final roleColor = roleStr == 'lead'
                      ? const Color(0xFFF59E0B)
                      : roleStr == 'technician'
                          ? AdminColors.primary
                          : AdminColors.info;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              AdminColors.primary.withAlpha(40),
                          backgroundImage:
                              eng['profile_photo'] != null
                                  ? NetworkImage(
                                      eng['profile_photo'] as String)
                                  : null,
                          child: eng['profile_photo'] == null
                              ? Text(
                                  (eng['full_name'] as String? ??
                                          '?')[0]
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: AdminColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(eng['full_name'] as String? ?? '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text(
                                '${eng['employee_id'] ?? '—'} • ${eng['assigned_zone'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AdminColors.textSub(context)),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: roleColor.withAlpha(26),
                                  borderRadius:
                                      BorderRadius.circular(Brand.r(5))),
                              child: Text(_capitalize(roleStr),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: roleColor,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _capitalize(engStatus),
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      AdminColors.textSub(context)),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline,
                              size: 18, color: AdminColors.error),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _removeEngineer(engId),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          )),
          const SizedBox(height: 12),

          // ── Admin notes ──
          if (_install['admin_notes'] != null)
            _card(context: context, isDark: isDark, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Admin Notes', context),
                const SizedBox(height: 8),
                Text(_install['admin_notes'] as String,
                    style: TextStyle(
                        fontSize: 14,
                        color: AdminColors.text(context))),
              ],
            )),

          // ── Completion report ──
          if (_install['completion_report'] != null) ...[
            const SizedBox(height: 12),
            _card(context: context, isDark: isDark, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.task_alt,
                        size: 16, color: AdminColors.success),
                    const SizedBox(width: 6),
                    Text('Completion Report',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.success)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_install['completion_report'] as String,
                    style: TextStyle(
                        fontSize: 14,
                        color: AdminColors.text(context))),
                if (_install['completed_at'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Completed: ${_fmtDateTime(_install['completed_at'] as String?)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(context)),
                  ),
                ],
              ],
            )),
          ],

          // ── Timestamps ──
          const SizedBox(height: 12),
          _card(context: context, isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Timeline', context),
              const SizedBox(height: 8),
              _row(Icons.add_circle_outline,
                  'Created: ${_fmtDateTime(_install['created_at'] as String?)}',
                  context),
              if (_install['confirmed_at'] != null) ...[
                const SizedBox(height: 4),
                _row(Icons.check_circle_outline,
                    'Confirmed: ${_fmtDateTime(_install['confirmed_at'] as String?)}',
                    context),
              ],
              if (_install['started_at'] != null) ...[
                const SizedBox(height: 4),
                _row(Icons.play_circle_outline,
                    'Started: ${_fmtDateTime(_install['started_at'] as String?)}',
                    context),
              ],
              if (_install['completed_at'] != null) ...[
                const SizedBox(height: 4),
                _row(Icons.done_all,
                    'Completed: ${_fmtDateTime(_install['completed_at'] as String?)}',
                    context),
              ],
              if (_install['cancelled_at'] != null) ...[
                const SizedBox(height: 4),
                _row(Icons.cancel_outlined,
                    'Cancelled: ${_fmtDateTime(_install['cancelled_at'] as String?)}',
                    context),
              ],
            ],
          )),
        ],
      ),
    );
  }

  Widget _card(
          {required BuildContext context,
          required bool isDark,
          required Widget child}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.card(context),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(color: AdminColors.border(context)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
        ),
        child: child,
      );

  Widget _badge(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(Brand.r(6))),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  Widget _sectionTitle(String title, BuildContext context) =>
      Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AdminColors.textSub(context)));

  Widget _row(IconData icon, String text, BuildContext context) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 15, color: AdminColors.textSub(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: AdminColors.text(context))),
          ),
        ],
      );

  Widget _actionBtn(
          String label, Color color, IconData icon, VoidCallback fn) =>
      ElevatedButton.icon(
        icon: Icon(icon, size: 15, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.r(10))),
        ),
        onPressed: fn,
      );
}
