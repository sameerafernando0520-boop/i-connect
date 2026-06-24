// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineer/engineer_installation_detail_page.dart
// Engineer — Installation detail with full status progression
// Flow: assigned → acknowledge → start work → complete
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _engAccent = Brand.cyanAccent;

const _typeLabels = {
  'new_install':   'New Install',
  'replacement':   'Replacement',
  'upgrade':       'Upgrade',
  'commissioning': 'Commissioning',
  'decommission':  'Decommission',
};
const _typeColors = {
  'new_install':   AdminColors.accent,
  'replacement':   StatusColors.assigned,
  'upgrade':       AdminColors.info,
  'commissioning': AdminColors.warning,
  'decommission':  AdminColors.error,
};
const _statusLabels = {
  'pending':     'Pending',
  'scheduled':   'Scheduled',
  'in_progress': 'In Progress',
  'completed':   'Completed',
  'cancelled':   'Cancelled',
};
const _statusColors = {
  'pending':     AdminColors.warning,
  'scheduled':   AdminColors.info,
  'in_progress': StatusColors.assigned,
  'completed':   AdminColors.accent,
  'cancelled':   AdminColors.textSecondary,
};

class EngineerInstallationDetailPage extends StatefulWidget {
  final String installationId;
  const EngineerInstallationDetailPage(
      {super.key, required this.installationId});

  @override
  State<EngineerInstallationDetailPage> createState() =>
      _EngineerInstallationDetailPageState();
}

class _EngineerInstallationDetailPageState
    extends State<EngineerInstallationDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _inst;
  Map<String, dynamic>? _myAssignment; // my row from installation_engineers
  bool _changed = false;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      // Full installation data
      final row = await SupabaseConfig.client
          .from('machine_installations')
          .select('''
            id, title, installation_type, status,
            scheduled_date, scheduled_time, estimated_duration_hours,
            location, admin_notes, engineer_notes, completion_report,
            created_at, confirmed_at, started_at, completed_at, cancelled_at,
            cancellation_reason,
            customer:users!customer_id(id, full_name, phone_number, address),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number, category)
            ),
            installation_engineers(
              id, role, status, assigned_at, acknowledged_at,
              engineer:users!engineer_id(id, full_name, phone_number, employee_id)
            )
          ''')
          .eq('id', widget.installationId)
          .single();

      if (!mounted) return;

      // Find my assignment row
      final myUid = uid;
      final engs = (row['installation_engineers'] as List? ?? []);
      final myEng = engs.cast<Map<String, dynamic>>().where((e) {
        final engUser = e['engineer'] as Map?;
        return engUser?['id'] == myUid;
      }).firstOrNull;

      setState(() {
        _inst = Map<String, dynamic>.from(row);
        _myAssignment = myEng != null
            ? Map<String, dynamic>.from(myEng)
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _acknowledge() async {
    setState(() => _actionLoading = true);
    try {
      await SupabaseConfig.client
          .rpc('engineer_acknowledge_installation', params: {
        'p_installation_id': widget.installationId,
      });
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed: ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _startWork() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text('Start Installation'),
        content: const Text(
            'Mark this installation as In Progress? This will notify the admin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _engAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      await SupabaseConfig.client
          .rpc('update_installation_status', params: {
        'p_installation_id': widget.installationId,
        'p_status': 'in_progress',
        'p_completion_report': null,
        'p_engineer_notes': null,
      });
      if (!mounted) return;
      _changed = true;
      _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed: ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _complete() async {
    final reportCtrl = TextEditingController();
    final notesCtrl  = TextEditingController(
        text: (_inst?['engineer_notes'] as String?) ?? '');

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('Mark as Completed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Completion Report',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: reportCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Describe what was done, results, issues…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Engineer Notes (optional)',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Internal notes for the team…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Completion',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      // Validate that completion report is not empty
      if (reportCtrl.text.trim().isEmpty) {
        if (mounted) {
          _showSnack('Please enter a completion report', error: true);
        }
        return;
      }

      setState(() => _actionLoading = true);
      try {
        await SupabaseConfig.client
            .rpc('update_installation_status', params: {
          'p_installation_id': widget.installationId,
          'p_status': 'completed',
          'p_completion_report': reportCtrl.text.trim(),
          'p_engineer_notes':
              notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        });
        if (!mounted) return;
        _changed = true;
        _load();
      } catch (e) {
        if (!mounted) return;
        _showSnack('Failed: ${e.toString()}', error: true);
      } finally {
        if (mounted) setState(() => _actionLoading = false);
      }
    } finally {
      reportCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  Future<void> _launchContact(String scheme, String value) async {
    final uri = Uri(scheme: scheme, path: value);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      _showSnack('Cannot open ${scheme == 'tel' ? 'phone dialer' : 'email app'}', error: true);
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
      backgroundColor: error ? StatusColors.danger : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
    ));
  }

  // ── Theme helpers ─────────────────────────────────────────────

  bool get _isDark =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _cardColor => Brand.surface(_isDark);

  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : Colors.black87;

  Color get _textSub =>
      _isDark ? Brand.darkTextSecondary : Colors.grey[600]!;

  Color get _borderColor =>
      _isDark ? Brand.darkBorder : Brand.borderLight;

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas(_isDark),
      appBar: DsPageHeader(
        title: 'Installation Detail',
        accent: HeroAccent.cyan,
        onBack: () => Navigator.pop(context, _changed),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _engAccent))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: StatusColors.danger.withAlpha(_isDark ? 25 : 15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  color: StatusColors.danger, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600,
                  color: _textPrimary,
                )),
            const SizedBox(height: 6),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _textSub)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: _engAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ]),
        ),
      );

  Widget _buildContent() {
    final inst     = _inst!;
    final myAssign = _myAssignment;
    final status   = inst['status'] as String? ?? 'pending';
    final type     = inst['installation_type'] as String? ?? 'new_install';
    final myStatus = myAssign?['status'] as String? ?? 'assigned';

    final statusColor = _statusColors[status] ?? AdminColors.textSecondary;
    final typeColor   = _typeColors[type] ?? AdminColors.textSecondary;

    final engineers = ((inst['installation_engineers'] as List?) ?? [])
        .where((e) => (e['status'] as String?) != 'removed')
        .toList();

    return RefreshIndicator(
      color: _engAccent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status progress stepper ──
          _buildProgressStepper(myStatus, status),
          const SizedBox(height: 16),

          // ── Action button area ──
          if (status != 'completed' && status != 'cancelled')
            _buildActionArea(myStatus, status),

          // ── Header card ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Text(_typeLabels[type] ?? type,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: typeColor)),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Text(_statusLabels[status] ?? status,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(inst['title'] ?? 'Untitled',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary)),
                if (myAssign != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.badge_outlined,
                        size: 14, color: _engAccent),
                    const SizedBox(width: 6),
                    Text(
                      'My Role: ${(myAssign['role'] as String?)?.toUpperCase() ?? 'TECHNICIAN'}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _engAccent),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Customer & Machine ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _sectionTitle('Customer & Machine'),
                    const Spacer(),
                    if (((inst['customer'] as Map?)?['phone_number'] as String?)?.isNotEmpty == true)
                      InkWell(
                        onTap: () => _launchContact('tel',
                            (inst['customer'] as Map?)!['phone_number'] as String),
                        borderRadius: BorderRadius.circular(Brand.r(8)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AdminColors.accent.withAlpha(_isDark ? 25 : 15),
                            borderRadius: BorderRadius.circular(Brand.r(8)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone, size: 14, color: AdminColors.accent),
                              SizedBox(width: 4),
                              Text('Call', style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: AdminColors.accent,
                              )),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _kv('Customer',
                    (inst['customer'] as Map?)?['full_name'] ?? '—'),
                _kvTappable(
                  'Phone',
                  (inst['customer'] as Map?)?['phone_number'] ?? '—',
                  onTap: ((inst['customer'] as Map?)?['phone_number'] as String?)?.isNotEmpty == true
                      ? () => _launchContact('tel',
                          (inst['customer'] as Map?)!['phone_number'] as String)
                      : null,
                ),
                if ((inst['customer'] as Map?)?['address'] != null)
                  _kv('Address',
                      (inst['customer'] as Map?)!['address'] as String),
                Divider(height: 20,
                    color: _isDark ? Brand.darkBorder : Brand.borderLight),
                _kv('Machine',
                    ((inst['machine'] as Map?)?['catalog'] as Map?)?['machine_name'] ??
                        '—'),
                _kv('Model',
                    ((inst['machine'] as Map?)?['catalog'] as Map?)?['model_number'] ??
                        '—'),
                _kv('Serial',
                    (inst['machine'] as Map?)?['serial_number'] ?? '—'),
                _kv('Category',
                    ((inst['machine'] as Map?)?['catalog'] as Map?)?[
                            'category'] ??
                        '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Schedule + Location ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Schedule & Location'),
                const SizedBox(height: 10),
                _kv('Date', inst['scheduled_date'] ?? '—'),
                _kv('Time', inst['scheduled_time'] ?? '—'),
                _kv('Est. Duration',
                    inst['estimated_duration_hours'] != null
                        ? '${inst['estimated_duration_hours']} hrs'
                        : '—'),
                _kv('Location', inst['location'] ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Team (other engineers) ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Installation Team'),
                const SizedBox(height: 10),
                if (engineers.isEmpty)
                  Text('No team members',
                      style: TextStyle(color: _textSub))
                else
                  ...engineers.map((e) => _teamRow(e)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Admin Notes (read-only) ──
          if ((inst['admin_notes'] as String?)?.isNotEmpty == true) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Admin Notes'),
                  const SizedBox(height: 8),
                  Text(inst['admin_notes']!,
                      style: TextStyle(color: _textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Completion report (visible once completed) ──
          if ((inst['completion_report'] as String?)?.isNotEmpty == true) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Completion Report'),
                  const SizedBox(height: 8),
                  Text(inst['completion_report']!,
                      style: TextStyle(color: _textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Timeline ──
          _card(
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
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Progress stepper ──────────────────────────────────────────

  Widget _buildProgressStepper(String myStatus, String instStatus) {
    final steps = [
      _Step('Assigned', 'assigned', Icons.assignment_outlined),
      _Step('Acknowledged', 'acknowledged', Icons.thumb_up_outlined),
      _Step('In Progress', 'in_progress', Icons.construction_rounded),
      _Step('Completed', 'completed', Icons.check_circle_outline),
    ];

    final order = ['assigned', 'acknowledged', 'in_progress', 'completed'];
    int currentIdx = order.indexOf(myStatus);
    if (instStatus == 'in_progress') currentIdx = order.indexOf('in_progress');
    if (instStatus == 'completed')   currentIdx = order.indexOf('completed');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final step    = steps[i];
          final done    = i <= currentIdx;
          final active  = i == currentIdx;
          final isLast  = i == steps.length - 1;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: done
                              ? _engAccent
                              : _isDark
                                  ? Brand.darkCardElevated
                                  : AdminColors.background,
                          shape: BoxShape.circle,
                          border: active
                              ? Border.all(
                                  color: _engAccent, width: 2)
                              : null,
                        ),
                        child: Icon(
                          step.icon,
                          size: 16,
                          color: done ? Colors.white : _textSub,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: done ? _engAccent : _textSub,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: i < currentIdx
                          ? _engAccent
                          : _isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Action area ───────────────────────────────────────────────

  Widget _buildActionArea(String myStatus, String instStatus) {
    // Only show if I'm not removed and installation is active
    if (_myAssignment == null) return const SizedBox.shrink();
    if (instStatus == 'cancelled') return const SizedBox.shrink();

    Widget? btn;

    if (myStatus == 'assigned') {
      // Show Acknowledge button
      btn = _actionBtn(
        label: 'Acknowledge Assignment',
        icon: Icons.thumb_up_outlined,
        color: AdminColors.info,
        onTap: _acknowledge,
      );
    } else if (myStatus == 'acknowledged' &&
        (instStatus == 'scheduled' || instStatus == 'pending')) {
      // Show Start Work button
      btn = _actionBtn(
        label: 'Start Installation Work',
        icon: Icons.play_arrow_rounded,
        color: StatusColors.assigned,
        onTap: _startWork,
      );
    } else if (instStatus == 'in_progress') {
      // Show Complete button
      btn = _actionBtn(
        label: 'Submit Completion Report',
        icon: Icons.check_circle_outline,
        color: AdminColors.accent,
        onTap: _complete,
      );
    }

    if (btn == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: btn,
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: _actionLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.r(14))),
        ),
        onPressed: _actionLoading ? null : onTap,
      ),
    );
  }

  // ── Team row ──────────────────────────────────────────────────

  Widget _teamRow(Map<String, dynamic> e) {
    final eng    = e['engineer'] as Map?;
    final name   = eng?['full_name'] ?? '—';
    final role   = e['role'] as String? ?? 'technician';
    final status = e['status'] as String? ?? 'assigned';
    final uid    = SupabaseConfig.client.auth.currentUser?.id;
    final isMe   = eng?['id'] == uid;

    Color dot;
    switch (status) {
      case 'acknowledged': dot = AdminColors.info; break;
      case 'in_progress':  dot = _engAccent; break;
      case 'completed':    dot = AdminColors.accent; break;
      default:             dot = AdminColors.warning;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
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
              Row(children: [
                Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _textPrimary)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _engAccent.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(6)),
                    ),
                    child: const Text('You',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _engAccent)),
                  ),
                ],
              ]),
              Text('${role.capitalize()} · $status',
                  style: TextStyle(fontSize: 12, color: _textSub)),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: _borderColor),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _engAccent,
          letterSpacing: 0.5));

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: TextStyle(fontSize: 13, color: _textSub)),
            ),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary)),
            ),
          ],
        ),
      );

  Widget _kvTappable(String k, String v, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: TextStyle(fontSize: 13, color: _textSub)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Row(
                  children: [
                    Text(v,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: onTap != null ? _engAccent : _textPrimary,
                          decoration: onTap != null ? TextDecoration.underline : null,
                          decorationColor: _engAccent,
                        )),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 12, color: _engAccent),
                    ],
                  ],
                ),
              ),
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

// ── Step model ────────────────────────────────────────────────

class _Step {
  final String label;
  final String key;
  final IconData icon;
  const _Step(this.label, this.key, this.icon);
}

// ── String extension ──────────────────────────────────────────

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
