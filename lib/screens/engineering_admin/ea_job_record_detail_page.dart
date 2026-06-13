// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_job_record_detail_page.dart
// Engineering Admin Portal — Screen 9: Job Record Detail
// Full view of a single job record with status controls and edit.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import 'ea_job_record_form_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaJobRecordDetailPage extends StatefulWidget {
  final String recordId;

  const EaJobRecordDetailPage({super.key, required this.recordId});

  @override
  State<EaJobRecordDetailPage> createState() => _EaJobRecordDetailPageState();
}

class _EaJobRecordDetailPageState extends State<EaJobRecordDetailPage> {
  Map<String, dynamic>? _record;
  bool _loading = true;
  String? _error;
  bool _changed = false;

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
      final data = await SupabaseConfig.client
          .from('job_records')
          .select('''
            *,
            engineer:users!engineer_id(
              id, full_name, profile_photo, employee_id, assigned_zone, phone_number
            ),
            ticket:service_tickets!ticket_id(
              id, ticket_number, subject, status, description
            )
          ''')
          .eq('id', widget.recordId)
          .single();

      if (!mounted) return;
      setState(() {
        _record = Map<String, dynamic>.from(data as Map);
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

  // ── Status update ─────────────────────────────────────────────

  Future<void> _updateStatus(String newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark ${_statusLabel(newStatus)}?'),
        content: Text(
          'Change this job record status to "${_statusLabel(newStatus)}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _statusColor(newStatus),
              foregroundColor: Colors.white,
            ),
            child: Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final payload = <String, dynamic>{'status': newStatus};

    await SupabaseConfig.client
        .from('job_records')
        .update(payload)
        .eq('id', widget.recordId);

    if (!mounted) return;
    _changed = true;
    _load();
  }

  // ── Delete ────────────────────────────────────────────────────

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Job Record?'),
        content: const Text(
          'This action cannot be undone. The job record will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SupabaseConfig.client
        .from('job_records')
        .delete()
        .eq('id', widget.recordId);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'in_progress':
        return const Color(0xFF3B82F6);
      case 'completed':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  String _jobTypeLabel(String? t) {
    switch (t) {
      case 'installation':
        return 'Installation';
      case 'repair':
        return 'Repair';
      case 'maintenance':
        return 'Maintenance';
      case 'inspection':
        return 'Inspection';
      case 'warranty':
        return 'Warranty Visit';
      default:
        return t ?? 'Job';
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        '',
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDateTime(String? isoStr) {
    if (isoStr == null) return '—';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day} ${months[dt.month]} ${dt.year}, $hour:$min $ampm';
    } catch (_) {
      return isoStr;
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Brand.canvas(isDark);
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // already handled
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cardBg,
          foregroundColor: textPrimary,
          elevation: 0,
          title: const Text(
            'Job Record',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            if (_record != null) ...[
              IconButton(
                onPressed: () async {
                  final edited = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EaJobRecordFormPage(
                        existingRecord: _record,
                      ),
                    ),
                  );
                  if (edited == true) {
                    _changed = true;
                    _load();
                  }
                },
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit',
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_rounded,
                            size: 18, color: Color(0xFFEF4444)),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _eaAccent))
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _load)
                : _record == null
                    ? const Center(child: Text('Record not found'))
                    : _buildContent(isDark, textPrimary),
      ),
    );
  }

  Widget _buildContent(bool isDark, Color textPrimary) {
    final r = _record!;
    final eng = r['engineer'] as Map<String, dynamic>?;
    final ticket = r['ticket'] as Map<String, dynamic>?;
    final status = r['status'] as String? ?? '';
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status header ──────────────────────────────────────
          _card(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _jobTypeLabel(r['job_type'] as String?),
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(r['job_date'] as String?),
                            style: TextStyle(
                                color: textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _statusColor(status).withAlpha(70)),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                // Duration + rating row
                const SizedBox(height: 12),
                if (r['duration_hours'] != null)
                  Row(
                    children: [
                      Icon(Icons.timer_rounded,
                          size: 15, color: textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${(r['duration_hours'] as num).toStringAsFixed(1)} hrs',
                        style:
                            TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Status actions ─────────────────────────────────────
          if (status != 'completed' && status != 'cancelled')
            _card(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Status',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (status == 'pending')
                        _actionChip(
                          label: 'Start Job',
                          icon: Icons.play_arrow_rounded,
                          color: const Color(0xFF3B82F6),
                          onTap: () => _updateStatus('in_progress'),
                        ),
                      if (status == 'in_progress' || status == 'pending')
                        _actionChip(
                          label: 'Complete',
                          icon: Icons.check_rounded,
                          color: const Color(0xFF10B981),
                          onTap: () => _updateStatus('completed'),
                        ),
                      _actionChip(
                        label: 'Cancel',
                        icon: Icons.cancel_rounded,
                        color: const Color(0xFFEF4444),
                        onTap: () => _updateStatus('cancelled'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (status != 'completed' && status != 'cancelled')
            const SizedBox(height: 12),

          // ── Engineer ───────────────────────────────────────────
          if (eng != null)
            _card(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ENGINEER',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _avatar(
                        photoUrl: eng['profile_photo'] as String?,
                        name: eng['full_name'] as String? ?? '',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eng['full_name'] as String? ?? '',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Zone: ${eng['assigned_zone'] ?? '—'}  ·  ID: ${eng['employee_id'] ?? '—'}',
                              style: TextStyle(
                                  color: textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // ── Linked ticket ──────────────────────────────────────
          if (ticket != null)
            _card(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LINKED TICKET',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${ticket['ticket_number'] ?? ''} · ${ticket['subject'] ?? ''}',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if ((ticket['description'] as String?)?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            ticket['description'] as String,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (ticket != null) const SizedBox(height: 12),

          // ── Job details ────────────────────────────────────────
          _card(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOB DETAILS',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                _infoRow(
                  label: 'Job Type',
                  value: _jobTypeLabel(r['job_type'] as String?),
                  isDark: isDark,
                ),
                _infoRow(
                  label: 'Job Date',
                  value: _formatDate(r['job_date'] as String?),
                  isDark: isDark,
                ),
                if (r['start_time'] != null)
                  _infoRow(
                    label: 'Start Time',
                    value: _formatDateTime(r['start_time'] as String?),
                    isDark: isDark,
                  ),
                if (r['end_time'] != null)
                  _infoRow(
                    label: 'End Time',
                    value: _formatDateTime(r['end_time'] as String?),
                    isDark: isDark,
                  ),
                if (r['duration_hours'] != null)
                  _infoRow(
                    label: 'Duration',
                    value:
                        '${(r['duration_hours'] as num).toStringAsFixed(1)} hours',
                    isDark: isDark,
                  ),
                if (r['location'] != null && (r['location'] as String).isNotEmpty)
                  _infoRow(
                    label: 'Location',
                    value: r['location'] as String,
                    isDark: isDark,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Notes / Outcome ────────────────────────────────────
          if ((r['notes'] as String?)?.isNotEmpty ?? false)
            _labelledText(
              label: 'NOTES',
              text: r['notes'] as String,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          if ((r['notes'] as String?)?.isNotEmpty ?? false)
            const SizedBox(height: 12),

          if ((r['outcome'] as String?)?.isNotEmpty ?? false)
            _labelledText(
              label: 'OUTCOME / FINDINGS',
              text: r['outcome'] as String,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          if ((r['outcome'] as String?)?.isNotEmpty ?? false)
            const SizedBox(height: 12),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────

  Widget _card({required bool isDark, required Widget child}) {
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _avatar({
    required String? photoUrl,
    required String name,
    required bool isDark,
  }) {
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _eaAccent.withAlpha(80), width: 2),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    _AvatarFallback(initials: initials, isDark: isDark),
                errorWidget: (_, __, ___) =>
                    _AvatarFallback(initials: initials, isDark: isDark),
              )
            : _AvatarFallback(initials: initials, isDark: isDark),
      ),
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    final textPrimary =
        isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary =
        isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ),
          Container(width: 1, height: 16, color: borderColor,
              margin: const EdgeInsets.only(right: 12)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelledText({
    required String label,
    required String text,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar Fallback ───────────────────────────────────────────────────────────

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

// ── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              'Failed to load job record',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextPrimary
                    : const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(error,
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
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
