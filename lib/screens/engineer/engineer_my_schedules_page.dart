// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineer/engineer_my_schedules_page.dart
// Shows every service_schedule this engineer is assigned to
// (via service_schedule_engineers join). Each card has lifecycle
// buttons that:
//   - Update service_schedule_engineers status + timestamps
//   - Update parent service_schedules status if lead
//   - Call fn_post_job_status_chat RPC (chat msg + customer notif)
//   - Optionally create a job_records row on completion
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _engAccent = Brand.cyanAccent;

class EngineerMySchedulesPage extends StatefulWidget {
  const EngineerMySchedulesPage({super.key});

  @override
  State<EngineerMySchedulesPage> createState() =>
      _EngineerMySchedulesPageState();
}

class _EngineerMySchedulesPageState extends State<EngineerMySchedulesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _assignments = [];
  String? _currentUserId;
  String _filter = 'today'; // today | upcoming | all

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    if (_currentUserId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = SupabaseConfig.client
          .from('service_schedule_engineers')
          .select('''
            id, schedule_id, role, status, assigned_at, notified_at,
            acknowledged_at, started_at, arrived_at, completed_at, notes,
            schedule:service_schedules!schedule_id(
              id, title, description, scheduled_date, scheduled_time,
              estimated_duration, status, service_location, location_lat,
              location_lng, ticket_id,
              customer:users!customer_id(id, full_name, phone_number, profile_photo)
            )
          ''')
          .eq('engineer_id', _currentUserId!);

      final res = await query.order('assigned_at', ascending: false);
      var list = List<Map<String, dynamic>>.from(res);

      // Local filter
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      if (_filter == 'today') {
        list = list.where((a) {
          final s = a['schedule'] as Map<String, dynamic>?;
          return s?['scheduled_date'] == todayStr;
        }).toList();
      } else if (_filter == 'upcoming') {
        list = list.where((a) {
          final s = a['schedule'] as Map<String, dynamic>?;
          final d = s?['scheduled_date'] as String?;
          if (d == null) return false;
          return d.compareTo(todayStr) >= 0 &&
              (a['status'] as String?) != 'completed';
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _assignments = list;
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

  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open phone dialer')),
      );
    }
  }

  Future<void> _action(
    Map<String, dynamic> assignment,
    String kind, // travelling | arrived | started | completed
  ) async {
    final scheduleId = assignment['schedule_id'] as String;
    final assignmentId = assignment['id'] as String;
    final now = DateTime.now().toUtc().toIso8601String();

    final updates = <String, dynamic>{};
    String? sseStatus;
    switch (kind) {
      case 'travelling':
        updates['started_at'] = now;
        sseStatus = 'travelling';
        break;
      case 'arrived':
        updates['arrived_at'] = now;
        sseStatus = 'on_site';
        break;
      case 'started':
        if (assignment['started_at'] == null) updates['started_at'] = now;
        sseStatus = 'on_site';
        break;
      case 'completed':
        updates['completed_at'] = now;
        sseStatus = 'completed';
        break;
    }
    if (sseStatus != null) updates['status'] = sseStatus;

    try {
      // 1) Update the per-engineer row
      await SupabaseConfig.client
          .from('service_schedule_engineers')
          .update(updates)
          .eq('id', assignmentId);

      // 2) Bump parent schedule timestamps when crossing thresholds
      final scheduleUpdates = <String, dynamic>{
        'updated_at': now,
      };
      if (kind == 'started' || kind == 'travelling') {
        scheduleUpdates['started_at'] = now;
        scheduleUpdates['status'] = 'in_progress';
      } else if (kind == 'completed') {
        scheduleUpdates['completed_at'] = now;
        scheduleUpdates['status'] = 'completed';
      }
      if (scheduleUpdates.length > 1) {
        await SupabaseConfig.client
            .from('service_schedules')
            .update(scheduleUpdates)
            .eq('id', scheduleId);
      }

      // 3) Chat + customer notification via RPC
      await SupabaseConfig.client.rpc(
        'fn_post_job_status_chat',
        params: {
          'p_schedule_id': scheduleId,
          'p_engineer_id': _currentUserId,
          'p_kind': kind,
          'p_note': null,
        },
      );

      // 4) On Complete, create a job_records row for the engineer
      if (kind == 'completed') {
        final schedule = assignment['schedule'] as Map<String, dynamic>?;
        final ticketId = schedule?['ticket_id'] as String?;
        final customer = schedule?['customer'] as Map<String, dynamic>?;
        try {
          await SupabaseConfig.client.from('job_records').insert({
            'ticket_id': ticketId,
            'schedule_id': scheduleId,
            'engineer_id': _currentUserId,
            'customer_id': customer?['id'],
            'job_date': DateTime.now().toUtc().toIso8601String().substring(0, 10),
            'start_time': assignment['started_at'] ?? now,
            'end_time': now,
            'job_type': 'service',
            'job_status': 'completed',
            'work_done':
                'Job completed. Engineer pressed Complete from My Schedules.',
          });
        } catch (jobErr) {
          AppLogger.error('ScheduleUpdate', 'Failed to create job_records', error: jobErr);
          rethrow;
        }

        // Update ticket status
        if (ticketId != null) {
          try {
            await SupabaseConfig.client.from('service_tickets').update({
              'status': 'resolved',
              'closed_at': now,
              'updated_at': now,
            }).eq('id', ticketId);
          } catch (ticketErr) {
            AppLogger.error('ScheduleUpdate', 'Failed to update ticket status', error: ticketErr);
            rethrow;
          }
        }
      }

      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'My Schedules',
        accent: HeroAccent.cyan,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                _chip('Today', 'today', isDark),
                const SizedBox(width: 8),
                _chip('Upcoming', 'upcoming', isDark),
                const SizedBox(width: 8),
                _chip('All', 'all', isDark),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Error: $_error',
                              style:
                                  TextStyle(color: StatusColors.danger)),
                        ),
                      )
                    : _assignments.isEmpty
                        ? _emptyState(isDark)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 6, 12, 16),
                              itemCount: _assignments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) =>
                                  _card(_assignments[i], isDark),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, bool isDark) {
    final selected = _filter == value;
    return InkWell(
      onTap: () {
        setState(() => _filter = value);
        _load();
      },
      borderRadius: BorderRadius.circular(Brand.r(20)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _engAccent
              : Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: selected
                ? _engAccent
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark ? Brand.darkTextPrimary : Brand.royalBlue),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_rounded,
                  size: 56,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight),
              const SizedBox(height: 12),
              Text(
                'No assignments here yet',
                style: TextStyle(
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlue,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When the engineering admin dispatches you, the visit will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _card(Map<String, dynamic> a, bool isDark) {
    final s = a['schedule'] as Map<String, dynamic>?;
    final customer = s?['customer'] as Map<String, dynamic>?;
    final role = (a['role'] as String?) ?? 'technician';
    final sseStatus = (a['status'] as String?) ?? 'assigned';
    final title = s?['title'] as String? ?? 'Service visit';
    final loc = s?['service_location'] as String? ?? '—';
    final dateStr = s?['scheduled_date'] as String?;
    final timeStr = s?['scheduled_time'] as String?;
    final whenLabel = _formatWhen(dateStr, timeStr);

    final showTravelling = sseStatus == 'assigned' ||
        sseStatus == 'notified' ||
        sseStatus == 'acknowledged';
    final showArrived = sseStatus == 'travelling';
    final showStart = sseStatus == 'on_site' && a['started_at'] == null;
    // BUG-22: require "Start work" before "Complete" so started_at is never null on job records
    final showComplete = sseStatus == 'on_site' && a['started_at'] != null;
    final isDone = sseStatus == 'completed';

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(
          color: isDone
              ? Brand.lightGreenBright.withAlpha(80)
              : _engAccent.withAlpha(60),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — customer + role badge
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _engAccent.withAlpha(40),
                backgroundImage:
                    (customer?['profile_photo'] as String?) != null
                        ? CachedNetworkImageProvider(
                            customer!['profile_photo'] as String)
                        : null,
                child: (customer?['profile_photo'] as String?) == null
                    ? Icon(Icons.person_rounded, color: _engAccent)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer?['full_name'] as String? ?? 'Customer',
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (role == 'lead')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const StatusColors.assigned,
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: const Text(
                    'LEAD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Meta row
          Row(
            children: [
              Icon(Icons.event_rounded,
                  size: 14,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight),
              const SizedBox(width: 4),
              Text(
                whenLabel,
                style: TextStyle(
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.place_rounded,
                  size: 14,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  loc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          // ── Contact Row ──
          if (customer != null && (customer['phone_number'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_outlined,
                    size: 13,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _callCustomer(customer['phone_number'] as String),
                  child: Text(
                    customer['phone_number'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: _engAccent,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: _engAccent,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _callCustomer(customer['phone_number'] as String),
                  borderRadius: BorderRadius.circular(Brand.r(6)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const AdminColors.accent.withAlpha(isDark ? 25 : 15),
                      borderRadius: BorderRadius.circular(Brand.r(6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone, size: 12, color: AdminColors.accent),
                        SizedBox(width: 3),
                        Text('Call', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AdminColors.accent,
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Status chip + actions
          Row(
            children: [
              _statusChip(sseStatus, isDark),
              const Spacer(),
              if (isDone)
                Text(
                  'Completed ${TimeUtils.getTimeAgo(DateTime.parse(a['completed_at']).toLocal())}',
                  style: TextStyle(
                    color: Brand.lightGreenBright,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (!isDone) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (showTravelling)
                  _actionBtn('On the way',
                      icon: Icons.directions_car_rounded,
                      color: AdminColors.info,
                      onTap: () => _action(a, 'travelling')),
                if (showArrived)
                  _actionBtn('Arrived',
                      icon: Icons.place_rounded,
                      color: AdminColors.warning,
                      onTap: () => _action(a, 'arrived')),
                if (showStart)
                  _actionBtn('Start work',
                      icon: Icons.play_arrow_rounded,
                      color: _engAccent,
                      onTap: () => _action(a, 'started')),
                if (showComplete)
                  _actionBtn('Complete',
                      icon: Icons.check_circle_rounded,
                      color: Brand.lightGreenBright,
                      onTap: () => _confirmComplete(a)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmComplete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as complete?'),
        content: const Text(
            'This will close the visit, create a job record, and notify the customer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Brand.lightGreenBright,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (ok == true) await _action(a, 'completed');
  }

  Widget _statusChip(String s, bool isDark) {
    Color c;
    String label;
    switch (s) {
      case 'notified':
      case 'assigned':
        c = AdminColors.info;
        label = 'Assigned';
        break;
      case 'acknowledged':
        c = AdminColors.info;
        label = 'Acknowledged';
        break;
      case 'travelling':
        c = AdminColors.warning;
        label = 'On the way';
        break;
      case 'on_site':
        c = _engAccent;
        label = 'On site';
        break;
      case 'completed':
        c = Brand.lightGreenBright;
        label = 'Completed';
        break;
      default:
        c = Brand.subtleLight;
        label = s;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(38),
        borderRadius: BorderRadius.circular(Brand.r(10)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: c, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _actionBtn(String label,
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(12))),
      ),
    );
  }

  String _formatWhen(String? date, String? time) {
    if (date == null) return 'TBD';
    try {
      final d = DateTime.parse(date);
      final tParts = (time ?? '00:00:00').split(':');
      final dt = DateTime(
        d.year,
        d.month,
        d.day,
        int.parse(tParts[0]),
        int.parse(tParts[1]),
      );
      return DateFormat('EEE, MMM d · h:mm a').format(dt);
    } catch (_) {
      return date;
    }
  }
}

