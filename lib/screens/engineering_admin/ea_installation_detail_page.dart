// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_installation_detail_page.dart
// EA Installation Detail — view installation + assign/remove engineers
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _eaAccent = Color(0xFF16A34A);

const _typeLabels = {
  'new_install':   'New Install',
  'replacement':   'Replacement',
  'upgrade':       'Upgrade',
  'commissioning': 'Commissioning',
  'decommission':  'Decommission',
};
const _typeColors = {
  'new_install':   Color(0xFF10B981),
  'replacement':   Color(0xFF8B5CF6),
  'upgrade':       Color(0xFF3B82F6),
  'commissioning': Color(0xFFF59E0B),
  'decommission':  Color(0xFFEF4444),
};
const _statusLabels = {
  'pending':     'Pending',
  'scheduled':   'Scheduled',
  'in_progress': 'In Progress',
  'completed':   'Completed',
  'cancelled':   'Cancelled',
};
const _statusColors = {
  'pending':     Color(0xFFF59E0B),
  'scheduled':   Color(0xFF3B82F6),
  'in_progress': Color(0xFF8B5CF6),
  'completed':   Color(0xFF10B981),
  'cancelled':   Color(0xFF6B7280),
};
const _engRoleLabels = {
  'lead':       'Lead',
  'technician': 'Technician',
  'assistant':  'Assistant',
};

class EaInstallationDetailPage extends StatefulWidget {
  final String installationId;
  const EaInstallationDetailPage({super.key, required this.installationId});

  @override
  State<EaInstallationDetailPage> createState() =>
      _EaInstallationDetailPageState();
}

class _EaInstallationDetailPageState extends State<EaInstallationDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _inst;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final row = await SupabaseConfig.client
          .from('machine_installations')
          .select('''
            id, title, installation_type, status,
            scheduled_date, scheduled_time, estimated_duration_hours,
            location, admin_notes, engineer_notes, completion_report,
            created_at, confirmed_at, started_at, completed_at, cancelled_at,
            cancellation_reason,
            customer:users!customer_id(id, full_name, phone_number, email),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number, category)
            ),
            installation_engineers(
              id, role, status, assigned_at, acknowledged_at,
              engineer:users!engineer_id(
                id, full_name, profile_photo, phone_number, employee_id
              )
            )
          ''')
          .eq('id', widget.installationId)
          .single();

      if (!mounted) return;
      setState(() { _inst = Map<String, dynamic>.from(row); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _updateStatus(String newStatus) async {
    String? completionReport;

    if (newStatus == 'completed') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.card(context),
          title: const Text('Mark as Completed'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Completion report (optional)…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.success),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark Completed',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      completionReport = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    } else if (newStatus == 'cancelled') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.card(context),
          title: const Text('Cancel Installation'),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Reason for cancellation…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Installation',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    try {
      await SupabaseConfig.client.rpc('update_installation_status', params: {
        'p_installation_id': widget.installationId,
        'p_status': newStatus,
        'p_completion_report': completionReport,
        'p_engineer_notes': null,
      });
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed: ${e.toString()}', error: true);
    }
  }

  Future<void> _showAssignSheet() async {
    // Load all engineers
    List<Map<String, dynamic>> engineers = [];
    try {
      final rows = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, profile_photo, phone_number, employee_id')
          .eq('role', 'engineer')
          .order('full_name');
      engineers = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _showSnack('Could not load engineers', error: true);
      return;
    }
    if (!mounted) return;

    // Current assigned engineers
    final currentEngIds = ((_inst?['installation_engineers'] as List?) ?? [])
        .where((e) => (e['status'] as String?) != 'removed')
        .map((e) => (e['engineer'] as Map?)?['id'] as String?)
        .whereType<String>()
        .toSet();

    final Map<String, bool> selected = {
      for (final id in currentEngIds) id: true,
    };
    final Map<String, String> roles = {
      for (final e in ((_inst?['installation_engineers'] as List?) ?? []))
        if ((e['engineer'] as Map?)?['id'] != null)
          (e['engineer'] as Map?)!['id'] as String: e['role'] as String? ?? 'technician',
    };

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx2, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, ctrl) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkBorderLight
                            : Brand.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('Assign Engineers',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: engineers.isEmpty
                        ? Center(
                            child: Text('No engineers available',
                                style: TextStyle(
                                    color: AdminColors.textSub(context))))
                        : ListView.builder(
                            controller: ctrl,
                            itemCount: engineers.length,
                            itemBuilder: (_, i) {
                              final eng = engineers[i];
                              final id = eng['id'] as String;
                              final name = eng['full_name'] ?? 'Unknown';
                              final isSelected = selected[id] == true;
                              final role = roles[id] ?? 'technician';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    value: isSelected,
                                    activeColor: _eaAccent,
                                    title: Text(name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AdminColors.text(context))),
                                    subtitle: Text(
                                        eng['employee_id'] ?? '',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AdminColors.textSub(
                                                context))),
                                    onChanged: (v) {
                                      setSheet(() {
                                        selected[id] = v == true;
                                        if (v == true && !roles.containsKey(id)) {
                                          roles[id] = 'technician';
                                        }
                                      });
                                    },
                                  ),
                                  if (isSelected)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 72, right: 16, bottom: 8),
                                      child: Wrap(
                                        spacing: 8,
                                        children: ['lead', 'technician', 'assistant']
                                            .map((r) => ChoiceChip(
                                                  label: Text(
                                                      _engRoleLabels[r] ?? r),
                                                  selected: role == r,
                                                  selectedColor:
                                                      _eaAccent.withAlpha(30),
                                                  checkmarkColor: _eaAccent,
                                                  labelStyle: TextStyle(
                                                    fontSize: 12,
                                                    color: role == r
                                                        ? _eaAccent
                                                        : AdminColors.textSub(
                                                            context),
                                                  ),
                                                  onSelected: (_) => setSheet(
                                                      () => roles[id] = r),
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                  ),
                  // Save button
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _eaAccent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _saveAssignments(
                              sheetCtx, selected, roles),
                          child: const Text('Save Assignments',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _saveAssignments(
    BuildContext sheetCtx,
    Map<String, bool> selected,
    Map<String, String> roles,
  ) async {
    final payload = selected.entries
        .where((e) => e.value)
        .map((e) => {'engineer_id': e.key, 'role': roles[e.key] ?? 'technician'})
        .toList();

    try {
      await SupabaseConfig.client.rpc('assign_installation_engineers', params: {
        'p_installation_id': widget.installationId,
        'p_engineers': payload,
      });
      if (!mounted || !sheetCtx.mounted) return;
      Navigator.pop(sheetCtx);
      _changed = true;
      _load();
      _showSnack('Engineers assigned successfully');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed: ${e.toString()}', error: true);
    }
  }

  Future<void> _removeEngineer(String engineerId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.card(context),
        title: const Text('Remove Engineer'),
        content: Text('Remove $name from this installation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await SupabaseConfig.client.rpc('remove_installation_engineer', params: {
        'p_installation_id': widget.installationId,
        'p_engineer_id': engineerId,
      });
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed: ${e.toString()}', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: error ? AdminColors.error : AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) Navigator.of(context);
      },
      child: Scaffold(
        backgroundColor: AdminColors.bg(context),
        appBar: DsPageHeader(
          title: 'Installation Detail',
          accent: HeroAccent.emerald,
          onBack: () => Navigator.pop(context, _changed),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildContent(isDark),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AdminColors.error, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: AdminColors.textSub(context))),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );

  Widget _buildContent(bool isDark) {
    final inst = _inst!;
    final status = inst['status'] as String? ?? 'pending';
    final type   = inst['installation_type'] as String? ?? 'new_install';

    final statusColor = _statusColors[status] ?? const Color(0xFF6B7280);
    final typeColor   = _typeColors[type]   ?? const Color(0xFF6B7280);

    final engineers = (inst['installation_engineers'] as List? ?? [])
        .where((e) => (e['status'] as String?) != 'removed')
        .toList();

    return RefreshIndicator(
      color: _eaAccent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status header ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_typeLabels[type] ?? type,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: typeColor)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_statusLabels[status] ?? status,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(inst['title'] ?? 'Untitled',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(context))),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Status action buttons (EA can update status) ──
          if (status == 'pending' || status == 'scheduled')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Mark In Progress'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _statusColors['in_progress'],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _updateStatus('in_progress'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _updateStatus('cancelled'),
                  ),
                ),
              ]),
            ),
          if (status == 'in_progress')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark Completed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _updateStatus('completed'),
                ),
              ),
            ),

          // ── Customer + Machine ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Customer & Machine'),
                const SizedBox(height: 10),
                _kv('Customer',
                    (inst['customer'] as Map?)?['full_name'] ?? '—'),
                _kv('Phone',
                    (inst['customer'] as Map?)?['phone_number'] ?? '—'),
                const Divider(height: 20),
                _kv('Machine',
                    ((inst['machine'] as Map?)?['catalog'] as Map?)?['machine_name'] ??
                        '—'),
                _kv('Model',
                    ((inst['machine'] as Map?)?['catalog'] as Map?)?['model_number'] ??
                        '—'),
                _kv('Serial',
                    (inst['machine'] as Map?)?['serial_number'] ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Schedule + location ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Schedule & Location'),
                const SizedBox(height: 10),
                _kv('Scheduled Date', inst['scheduled_date'] ?? '—'),
                _kv('Scheduled Time', inst['scheduled_time'] ?? '—'),
                _kv('Est. Duration',
                    inst['estimated_duration_hours'] != null
                        ? '${inst['estimated_duration_hours']} hrs'
                        : '—'),
                _kv('Location', inst['location'] ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Engineers card ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _sectionTitle('Assigned Engineers')),
                    if (status != 'completed' && status != 'cancelled')
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 16),
                        label: const Text('Assign'),
                        style: TextButton.styleFrom(
                            foregroundColor: _eaAccent),
                        onPressed: _showAssignSheet,
                      ),
                  ],
                ),
                if (engineers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No engineers assigned yet',
                        style: TextStyle(
                            color: AdminColors.textSub(context),
                            fontStyle: FontStyle.italic)),
                  )
                else
                  ...engineers.map((e) => _engRow(e, isDark, status)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Admin notes ──
          if ((inst['admin_notes'] as String?)?.isNotEmpty == true)
            _card(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Admin Notes'),
                  const SizedBox(height: 8),
                  Text(inst['admin_notes']!,
                      style: TextStyle(color: AdminColors.text(context))),
                ],
              ),
            ),
          if ((inst['admin_notes'] as String?)?.isNotEmpty == true)
            const SizedBox(height: 12),

          // ── Completion report ──
          if ((inst['completion_report'] as String?)?.isNotEmpty == true)
            _card(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Completion Report'),
                  const SizedBox(height: 8),
                  Text(inst['completion_report']!,
                      style: TextStyle(color: AdminColors.text(context))),
                ],
              ),
            ),
          if ((inst['completion_report'] as String?)?.isNotEmpty == true)
            const SizedBox(height: 12),

          // ── Timeline ──
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Timeline'),
                const SizedBox(height: 10),
                _kv('Created', _fmt(inst['created_at'])),
                if (inst['confirmed_at'] != null)
                  _kv('Confirmed', _fmt(inst['confirmed_at'])),
                if (inst['started_at'] != null)
                  _kv('Started', _fmt(inst['started_at'])),
                if (inst['completed_at'] != null)
                  _kv('Completed', _fmt(inst['completed_at'])),
                if (inst['cancelled_at'] != null)
                  _kv('Cancelled', _fmt(inst['cancelled_at'])),
                if ((inst['cancellation_reason'] as String?)?.isNotEmpty == true)
                  _kv('Reason', inst['cancellation_reason']!),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  Widget _engRow(
      Map<String, dynamic> e, bool isDark, String installStatus) {
    final eng = e['engineer'] as Map?;
    final name = eng?['full_name'] ?? '—';
    final role = e['role'] as String? ?? 'technician';
    final engStatus = e['status'] as String? ?? 'assigned';
    final engId = eng?['id'] as String?;

    Color dot;
    switch (engStatus) {
      case 'acknowledged': dot = AdminColors.info; break;
      case 'in_progress':  dot = _eaAccent; break;
      case 'completed':    dot = AdminColors.success; break;
      default:             dot = AdminColors.warning;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AdminColors.text(context))),
                Text('${_engRoleLabels[role] ?? role} · $engStatus',
                    style: TextStyle(
                        fontSize: 12, color: AdminColors.textSub(context))),
              ],
            ),
          ),
          if (installStatus != 'completed' &&
              installStatus != 'cancelled' &&
              engId != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AdminColors.error, size: 20),
              tooltip: 'Remove',
              onPressed: () => _removeEngineer(engId, name),
            ),
        ],
      ),
    );
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _eaAccent,
          letterSpacing: 0.5));

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: TextStyle(
                      fontSize: 13, color: AdminColors.textSub(context))),
            ),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AdminColors.text(context))),
            ),
          ],
        ),
      );

  String _fmt(dynamic ts) {
    if (ts == null) return '—';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.toString();
    }
  }
}
