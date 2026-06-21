import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _eaAccent = Brand.lightGreenDark;

class EaLeaveDetailPage extends StatefulWidget {
  final String leaveId;
  const EaLeaveDetailPage({super.key, required this.leaveId});

  @override
  State<EaLeaveDetailPage> createState() => _EaLeaveDetailPageState();
}

class _EaLeaveDetailPageState extends State<EaLeaveDetailPage> {
  Map<String, dynamic>? _leave;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseConfig.client
          .from('engineer_leaves')
          .select('*, engineer:users!engineer_id(id, full_name, profile_photo, employee_id, assigned_zone, phone_number)')
          .eq('id', widget.leaveId)
          .maybeSingle();

      if (!mounted) return;
      if (data == null) {
        setState(() {
          _error = 'Leave record not found.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _leave = Map<String, dynamic>.from(data);
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

  Future<void> _approve() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Leave'),
        content: const Text('Approve this leave application? The engineer will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: StatusColors.resolved),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _updateStatus('approved', null);
  }

  Future<void> _reject() async {
    final noteCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reject this leave application?'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason (optional)',
                border: OutlineInputBorder(),
                hintText: 'Provide a reason for the engineer…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.error),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirm != true || !mounted) return;
    await _updateStatus('rejected', note.isNotEmpty ? note : null);
  }

  Future<void> _updateStatus(String newStatus, String? reviewNote) async {
    try {
      final payload = <String, dynamic>{
        'status': newStatus,
        'reviewed_by': SupabaseConfig.client.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (reviewNote != null) payload['review_note'] = reviewNote;

      await SupabaseConfig.client
          .from('engineer_leaves')
          .update(payload)
          .eq('id', widget.leaveId);

      if (!mounted) return;
      _changed = true;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 'approved' ? 'Leave approved' : 'Leave rejected'),
          backgroundColor: newStatus == 'approved' ? StatusColors.resolved : AdminColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _changed) Navigator.pop(context, true);
      },
      child: Scaffold(
        backgroundColor: AdminColors.bg(context),
        appBar: DsPageHeader(
          title: 'Leave Application',
          accent: HeroAccent.emerald,
          onBack: () => Navigator.pop(context, _changed ? true : null),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final leave = _leave!;
    final eng = leave['engineer'] as Map<String, dynamic>? ?? {};
    final status = leave['status'] as String? ?? 'pending';
    final isPending = status == 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status header
          _statusHeader(leave, isDark),
          const SizedBox(height: 14),

          // Action buttons — pending only
          if (isPending) ...[
            _actionButtons(),
            const SizedBox(height: 14),
          ],

          // Engineer card
          _card(
            context: context,
            isDark: isDark,
            title: 'Engineer',
            child: _engineerRow(eng),
          ),
          const SizedBox(height: 12),

          // Leave details card
          _card(
            context: context,
            isDark: isDark,
            title: 'Leave Details',
            child: Column(
              children: [
                _infoRow(context, 'Type', _leaveTypeLabel(leave['leave_type'] as String?)),
                _infoRow(context, 'Start Date', _fmt(leave['start_date'])),
                _infoRow(context, 'End Date', _fmt(leave['end_date'])),
                _infoRow(context, 'Duration', _durationLabel(leave)),
                _infoRow(context, 'Half Day', leave['is_half_day'] == true ? 'Yes' : 'No'),
                if (leave['is_half_day'] == true && leave['half_day_period'] != null)
                  _infoRow(context, 'Period', _capitalize(leave['half_day_period'] as String? ?? '')),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Reason
          if ((leave['reason'] as String?)?.isNotEmpty == true)
            _card(
              context: context,
              isDark: isDark,
              title: 'Reason',
              child: Text(
                leave['reason'] as String,
                style: TextStyle(fontSize: 14, color: AdminColors.textSub(context), height: 1.5),
              ),
            ),

          if ((leave['reason'] as String?)?.isNotEmpty == true) const SizedBox(height: 12),

          // Supporting document
          if ((leave['document_url'] as String?)?.isNotEmpty == true)
            _card(
              context: context,
              isDark: isDark,
              title: 'Supporting Document',
              child: Row(
                children: [
                  Icon(Icons.attach_file_rounded, size: 18, color: _eaAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Document attached',
                      style: TextStyle(color: _eaAccent, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          if ((leave['document_url'] as String?)?.isNotEmpty == true) const SizedBox(height: 12),

          // Review info (non-pending)
          if (!isPending)
            _card(
              context: context,
              isDark: isDark,
              title: 'Review Information',
              child: Column(
                children: [
                  _infoRow(context, 'Status', _statusLabel(status)),
                  if (leave['reviewed_at'] != null)
                    _infoRow(context, 'Reviewed At', _fmtDateTime(leave['reviewed_at'])),
                  if ((leave['review_note'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _labelledText(context, 'Notes', leave['review_note'] as String),
                    ),
                ],
              ),
            ),

          if (!isPending) const SizedBox(height: 12),

          // Submission info
          _card(
            context: context,
            isDark: isDark,
            title: 'Submission',
            child: Column(
              children: [
                _infoRow(context, 'Applied On', _fmtDateTime(leave['created_at'])),
                if (leave['updated_at'] != null)
                  _infoRow(context, 'Last Updated', _fmtDateTime(leave['updated_at'])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── sub-widgets ──────────────────────────────────────────────────────────────

  Widget _statusHeader(Map<String, dynamic> leave, bool isDark) {
    final status = leave['status'] as String? ?? 'pending';
    final statusColor = _statusColor(status);
    final leaveType = leave['leave_type'] as String?;
    final typeColor = _leaveTypeColor(leaveType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(15),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: statusColor.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: typeColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(_leaveTypeIcon(leave['leave_type'] as String?), color: typeColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _leaveTypeLabel(leave['leave_type'] as String?),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.text(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _durationLabel(leave),
                  style: TextStyle(fontSize: 12, color: AdminColors.textSub(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(25),
              borderRadius: BorderRadius.circular(Brand.r(20)),
              border: Border.all(color: statusColor.withAlpha(80)),
            ),
            child: Text(
              _statusLabel(status),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _reject,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.error,
              side: const BorderSide(color: AdminColors.error),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _approve,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: StatusColors.resolved,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _engineerRow(Map<String, dynamic> eng) {
    final photoUrl = eng['profile_photo'] as String?;
    final name = eng['full_name'] as String? ?? 'Engineer';
    final zone = eng['assigned_zone'] as String?;
    final empId = eng['employee_id'] as String?;
    final phone = eng['phone_number'] as String?;

    return Row(
      children: [
        _avatar(photoUrl, name, 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AdminColors.text(context),
                  )),
              if (empId != null || zone != null)
                Text(
                  [if (empId != null) '#$empId', if (zone != null) zone].join(' · '),
                  style: TextStyle(fontSize: 12, color: AdminColors.textHint(context)),
                ),
              if (phone != null)
                Text(phone, style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(String? url, String name, double size) {
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallbackAvatar(name, size),
          errorWidget: (_, __, ___) => _fallbackAvatar(name, size),
        ),
      );
    }
    return _fallbackAvatar(name, size);
  }

  Widget _fallbackAvatar(String name, double size) {
    final initials = name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _eaAccent.withAlpha(40), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: _eaAccent)),
    );
  }

  Widget _card({
    required BuildContext context,
    required bool isDark,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
        boxShadow: isDark
            ? []
            : [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.textHint(context),
                letterSpacing: 0.5,
              )),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AdminColors.text(context),
                )),
          ),
        ],
      ),
    );
  }

  Widget _labelledText(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: AdminColors.textHint(context), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontSize: 13, color: AdminColors.textSub(context), height: 1.5)),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmt(dynamic d) {
  if (d == null) return '—';
  try {
    return DateFormat('EEEE, d MMM yyyy').format(DateTime.parse(d.toString()));
  } catch (_) {
    return d.toString();
  }
}

String _fmtDateTime(dynamic d) {
  if (d == null) return '—';
  try {
    return DateFormat('d MMM yyyy, HH:mm').format(DateTime.parse(d.toString()).toLocal());
  } catch (_) {
    return d.toString();
  }
}

String _durationLabel(Map<String, dynamic> leave) {
  final days = (leave['total_days'] as num?)?.toDouble() ?? 1.0;
  final start = leave['start_date'] as String?;
  final end = leave['end_date'] as String?;
  String dateStr = '';
  if (start != null) {
    final fmt = DateFormat('d MMM');
    final s = fmt.format(DateTime.tryParse(start) ?? DateTime.now());
    if (end != null && end != start) {
      final e = fmt.format(DateTime.tryParse(end) ?? DateTime.now());
      dateStr = '$s – $e';
    } else {
      dateStr = s;
    }
  }
  final dayStr = '$days ${days == 1 ? 'day' : 'days'}';
  return dateStr.isNotEmpty ? '$dayStr ($dateStr)' : dayStr;
}

String _statusLabel(String? s) {
  switch (s) {
    case 'pending': return 'Pending';
    case 'approved': return 'Approved';
    case 'rejected': return 'Rejected';
    case 'cancelled': return 'Cancelled';
    default: return s ?? '—';
  }
}

Color _statusColor(String? s) {
  switch (s) {
    case 'pending': return AdminColors.warning;
    case 'approved': return StatusColors.resolved;
    case 'rejected': return AdminColors.error;
    case 'cancelled': return Brand.subtleLight;
    default: return Brand.subtleLight;
  }
}

Color _leaveTypeColor(String? t) {
  switch (t) {
    case 'sick': return AdminColors.error;
    case 'casual': return AdminColors.info;
    case 'annual': return StatusColors.resolved;
    case 'emergency': return AdminColors.error;
    case 'maternity': return StatusColors.pink;
    case 'paternity': return StatusColors.assigned;
    default: return Brand.subtleLight;
  }
}

String _leaveTypeLabel(String? t) {
  switch (t) {
    case 'sick': return 'Sick Leave';
    case 'casual': return 'Casual Leave';
    case 'annual': return 'Annual Leave';
    case 'emergency': return 'Emergency Leave';
    case 'maternity': return 'Maternity Leave';
    case 'paternity': return 'Paternity Leave';
    default: return (t ?? 'Leave');
  }
}

IconData _leaveTypeIcon(String? t) {
  switch (t) {
    case 'sick': return Icons.local_hospital_rounded;
    case 'casual': return Icons.weekend_rounded;
    case 'annual': return Icons.beach_access_rounded;
    case 'emergency': return Icons.warning_amber_rounded;
    case 'maternity': return Icons.child_care_rounded;
    case 'paternity': return Icons.family_restroom_rounded;
    default: return Icons.event_rounded;
  }
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AdminColors.error.withAlpha(180)),
            const SizedBox(height: 12),
            Text('Failed to load', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.text(context))),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AdminColors.textSub(context))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: _eaAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
