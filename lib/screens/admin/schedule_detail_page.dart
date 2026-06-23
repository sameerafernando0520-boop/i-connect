import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import '../../widgets/admin/shimmer_loading.dart';
import '../../widgets/admin/confirm_dialog.dart';

// ── Helpers ──

Color _typeColor(String? t) {
  switch (t) {
    case 'preventive':
      return const Color(0xFF3B82F6);
    case 'repair':
      return const Color(0xFFEF4444);
    case 'inspection':
      return const Color(0xFF14B8A6);
    case 'installation':
      return const Color(0xFF8B5CF6);
    case 'warranty_visit':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF6B7280);
  }
}

String _typeLabel(String? t) {
  switch (t) {
    case 'preventive':
      return 'Preventive Maintenance';
    case 'repair':
      return 'Repair';
    case 'inspection':
      return 'Inspection';
    case 'installation':
      return 'Installation';
    case 'warranty_visit':
      return 'Warranty Visit';
    default:
      return t ?? 'Unknown';
  }
}

IconData _typeIcon(String? t) {
  switch (t) {
    case 'preventive':
      return Icons.build_circle_outlined;
    case 'repair':
      return Icons.handyman;
    case 'inspection':
      return Icons.search;
    case 'installation':
      return Icons.precision_manufacturing;
    case 'warranty_visit':
      return Icons.verified_user;
    default:
      return Icons.event;
  }
}

String _statusLabel(String? s) {
  switch (s) {
    case 'requested':
      return 'Requested';
    case 'scheduled':
      return 'Scheduled';
    case 'confirmed':
      return 'Confirmed';
    case 'in_progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'rescheduled':
      return 'Rescheduled';
    default:
      return s ?? 'Unknown';
  }
}

String _fmtTime(String? t) {
  if (t == null || t.isEmpty) return '';
  final p = t.split(':');
  if (p.length < 2) return t;
  final h = int.tryParse(p[0]) ?? 0;
  final m = int.tryParse(p[1]) ?? 0;
  final period = h >= 12 ? 'PM' : 'AM';
  final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
  return '$dh:${m.toString().padLeft(2, '0')} $period';
}

String _fmtDuration(int? minutes) {
  if (minutes == null) return '';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m > 0 ? '${h}h ${m}m' : '${h}h';
}

String _capitalizeFirst(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

// ─────────────────────────────────────────────────────────────

class ScheduleDetailPage extends StatefulWidget {
  final String scheduleId;
  const ScheduleDetailPage({super.key, required this.scheduleId});

  @override
  State<ScheduleDetailPage> createState() => _ScheduleDetailPageState();
}

class _ScheduleDetailPageState extends State<ScheduleDetailPage> {
  Map<String, dynamic>? _schedule;
  bool _loading = true;
  bool _hasError = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data Loading ──

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final data = await SupabaseConfig.client
          .from('service_schedules')
          .select('''
            *,
            customer:users!customer_id(
              id, full_name, phone_number, profile_photo, company_name, email
            ),
            engineer:users!engineer_id(
              id, full_name, phone_number, profile_photo, email
            )
          ''')
          .eq('id', widget.scheduleId)
          .maybeSingle(); // ← was .single() — crashes if deleted

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _schedule = null;
          _loading = false;
        });
        return;
      }

      Map<String, dynamic> schedule = Map<String, dynamic>.from(data);

      // Fetch linked machine
      final machineId = schedule['customer_machine_id'];
      if (machineId != null) {
        try {
          final machine =
              await SupabaseConfig.client.from('customer_machines').select('''
                id, serial_number,
                catalog:machine_catalog!catalog_machine_id(
                  machine_name, model_number, image_url
                )
              ''').eq('id', machineId as String).maybeSingle();
          if (!mounted) return;
          if (machine != null) {
            schedule = {...schedule, 'machine': machine};
          }
        } catch (_) {}
      }

      // Fetch linked ticket
      final ticketId = schedule['ticket_id'];
      if (ticketId != null) {
        try {
          final ticket = await SupabaseConfig.client
              .from('service_tickets')
              .select('id, ticket_number, subject, status')
              .eq('id', ticketId as String)
              .maybeSingle();
          if (!mounted) return;
          if (ticket != null) {
            schedule = {...schedule, 'ticket': ticket};
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  // ── Status Update ──

  Future<void> _updateStatus(String newStatus, {String? reason}) async {
    setState(() => _acting = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final updates = <String, dynamic>{
        'status': newStatus,
        'updated_at': now,
      };

      switch (newStatus) {
        case 'confirmed':
          updates['confirmed_at'] = now;
          break;
        case 'in_progress':
          updates['started_at'] = now;
          break;
        case 'completed':
          updates['completed_at'] = now;
          break;
        case 'cancelled':
          updates['cancelled_at'] = now;
          if (reason != null) updates['cancellation_reason'] = reason;
          break;
      }

      await SupabaseConfig.client
          .from('service_schedules')
          .update(updates)
          .eq('id', widget.scheduleId);

      if (!mounted) return;
      _snack('Status updated to ${_statusLabel(newStatus)}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to update status', isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ── Reschedule ──

  Future<void> _reschedule() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Brand.royalBlue,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    if (newDate == null) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Brand.royalBlue,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    if (newTime == null) return;

    setState(() => _acting = true);
    try {
      final s = _schedule!;
      final timeStr =
          '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}:00';
      final dateStr =
          '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}';

      // Mark current as rescheduled
      await SupabaseConfig.client.from('service_schedules').update({
        'status': 'rescheduled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.scheduleId);

      if (!mounted) return;

      // Create new schedule
      await SupabaseConfig.client.from('service_schedules').insert({
        'customer_id': s['customer_id'],
        'engineer_id': s['engineer_id'],
        'customer_machine_id': s['customer_machine_id'],
        'ticket_id': s['ticket_id'],
        'schedule_type': s['schedule_type'],
        'title': s['title'],
        'description': s['description'],
        'scheduled_date': dateStr,
        'scheduled_time': timeStr,
        'estimated_duration': s['estimated_duration'],
        'service_location': s['service_location'],
        'is_recurring': s['is_recurring'],
        'recurrence_rule': s['recurrence_rule'],
        'parent_schedule_id': widget.scheduleId,
        'admin_notes': s['admin_notes'],
        'customer_notes': s['customer_notes'],
        'status': 'scheduled',
        'created_by': SupabaseConfig.client.auth.currentUser!.id,
      });

      if (!mounted) return;
      _snack('Rescheduled successfully');
      await _load();
    } catch (_) {
      if (!mounted) return;
      _snack('Failed to reschedule', isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ── Cancel Dialog ──

  Future<void> _showCancelDialog() async {
    final reasonCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Brand.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(16))),
        title: Text(
          'Cancel Schedule',
          style: TextStyle(
            color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel this schedule?',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: TextStyle(
                color:
                    isDark ? Brand.darkTextPrimary : AdminColors.text(context),
              ),
              decoration: InputDecoration(
                hintText: 'Reason for cancellation (optional)',
                hintStyle: TextStyle(
                  color: isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Keep Schedule',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSub(context),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.error,
            ),
            child: const Text('Cancel Schedule'),
          ),
        ],
      ),
    );

    // Dispose before any await to prevent memory leak
    final reason =
        reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (!mounted) return;
    if (confirmed == true) {
      await _updateStatus('cancelled', reason: reason);
    }
  }

  // ── Delete ──

  Future<void> _delete() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Schedule',
      message: 'This cannot be undone. Delete this schedule permanently?',
      confirmLabel: 'Delete',
      confirmColor: AdminColors.error,
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _acting = true);
    try {
      await SupabaseConfig.client
          .from('service_schedules')
          .delete()
          .eq('id', widget.scheduleId);
      if (!mounted) return;
      _snack('Schedule deleted');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      _snack('Failed to delete schedule', isError: true);
      setState(() => _acting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AdminColors.error : AdminColors.success,
      ),
    );
  }

  bool _isTerminal(String? status) =>
      status == 'completed' || status == 'cancelled' || status == 'rescheduled';

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Schedule Details',
        accent: HeroAccent.navy,
        actions: [
          if (_schedule != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: Brand.surface(isDark),
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AdminColors.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete Schedule',
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextPrimary
                            : AdminColors.text(context),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : _hasError
              ? _buildErrorState(isDark)
              : _schedule == null
                  ? _buildNotFoundState(isDark)
                  : RefreshIndicator(
                      color: Brand.royalBlue,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildHeroCard(isDark),
                          const SizedBox(height: 16),
                          _buildDateTimeCard(isDark),
                          const SizedBox(height: 12),
                          _buildPeopleSection(isDark),
                          if (_schedule!['machine'] != null) ...[
                            const SizedBox(height: 12),
                            _buildMachineCard(isDark),
                          ],
                          if ((_schedule!['service_location'] as String?)
                                  ?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 12),
                            _buildLocationCard(isDark),
                          ],
                          if (_schedule!['ticket'] != null) ...[
                            const SizedBox(height: 12),
                            _buildTicketCard(isDark),
                          ],
                          const SizedBox(height: 12),
                          _buildNotesCard(isDark),
                          if (_schedule!['status'] == 'completed') ...[
                            const SizedBox(height: 12),
                            _buildServiceReportCard(isDark),
                          ],
                          if (!_isTerminal(
                              _schedule!['status'] as String?)) ...[
                            const SizedBox(height: 24),
                            _buildActionButtons(isDark),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
    );
  }

  // ── Hero Card ──

  Widget _buildHeroCard(bool isDark) {
    final s = _schedule!;
    final type = s['schedule_type'] as String? ?? '';
    final status = s['status'] as String? ?? '';
    final title = s['title'] as String? ?? 'Untitled';
    final desc = s['description'] as String? ?? '';
    final isRecurring = s['is_recurring'] == true;
    final rule = s['recurrence_rule'] as String? ?? '';
    final typeClr = _typeColor(type);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [typeClr, typeClr.withAlpha(179)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Brand.r(20)),
        boxShadow: [
          BoxShadow(
            color: typeClr.withAlpha(60),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Type + Status row ──
          Row(
            children: [
              Icon(
                _typeIcon(type),
                color: Colors.white.withAlpha(230),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _typeLabel(type),
                style: TextStyle(
                  color: Colors.white.withAlpha(204),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(Brand.r(8)),
                ),
                child: Text(
                  _statusLabel(status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Title ──
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),

          // ── Description ──
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 14,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // ── Recurring indicator ──
          if (isRecurring && rule.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(Brand.r(8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat,
                    color: Colors.white.withAlpha(204),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Recurring · ${_capitalizeFirst(rule)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(204),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Date / Time Card ──

  Widget _buildDateTimeCard(bool isDark) {
    final s = _schedule!;
    final dateStr = s['scheduled_date'] as String? ?? '';
    final timeStr = s['scheduled_time'] as String?;
    final duration = s['estimated_duration'] as int?;

    DateTime? date;
    try {
      if (dateStr.isNotEmpty) date = DateTime.parse(dateStr);
    } catch (_) {}

    final confirmedAt = s['confirmed_at'] as String?;
    final startedAt = s['started_at'] as String?;
    final completedAt = s['completed_at'] as String?;

    return _card(isDark, label: 'Date & Time', icon: Icons.schedule, children: [
      _infoRow(
        Icons.calendar_today,
        'Date',
        date != null ? TimeUtils.formatDateFull(date) : dateStr,
        isDark,
      ),
      const SizedBox(height: 10),
      _infoRow(
        Icons.access_time,
        'Time',
        _fmtTime(timeStr),
        isDark,
      ),
      if (duration != null) ...[
        const SizedBox(height: 10),
        _infoRow(
          Icons.timelapse,
          'Duration',
          _fmtDuration(duration),
          isDark,
        ),
      ],
      if (confirmedAt != null) ...[
        const SizedBox(height: 10),
        _infoRow(
          Icons.check_circle_outline,
          'Confirmed',
          TimeUtils.formatDateTime(DateTime.parse(confirmedAt).toLocal()),
          isDark,
        ),
      ],
      if (startedAt != null) ...[
        const SizedBox(height: 10),
        _infoRow(
          Icons.play_circle_outline,
          'Started',
          TimeUtils.formatDateTime(DateTime.parse(startedAt).toLocal()),
          isDark,
        ),
      ],
      if (completedAt != null) ...[
        const SizedBox(height: 10),
        _infoRow(
          Icons.check_circle,
          'Completed',
          TimeUtils.formatDateTime(DateTime.parse(completedAt).toLocal()),
          isDark,
        ),
      ],
    ]);
  }

  // ── People Section ──

  Widget _buildPeopleSection(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: _buildPersonCard(
          isDark: isDark,
          person: _schedule!['customer'] as Map<String, dynamic>?,
          label: 'Customer',
          color: Brand.royalBlue,
          fallbackIcon: Icons.person_outline,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _buildPersonCard(
          isDark: isDark,
          person: _schedule!['engineer'] as Map<String, dynamic>?,
          label: 'Engineer',
          color: const Color(0xFF14B8A6),
          fallbackIcon: Icons.engineering_outlined,
        )),
      ],
    );
  }

  Widget _buildPersonCard({
    required bool isDark,
    required Map<String, dynamic>? person,
    required String label,
    required Color color,
    required IconData fallbackIcon,
  }) {
    final name = person?['full_name'] as String? ?? 'Unassigned';
    final company = person?['company_name'] as String?;
    final phone = person?['phone_number'] as String?;
    final photo = person?['profile_photo'] as String?;
    final hasPhoto = photo != null && photo.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 10),

          // Avatar
          Center(
            child: CircleAvatar(
              radius: 28,
              backgroundColor: color.withAlpha(26),
              backgroundImage:
                  hasPhoto ? CachedNetworkImageProvider(photo) : null,
              child: hasPhoto
                  ? null
                  : (person != null
                      ? Text(
                          StringUtils.getInitials(name),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        )
                      : Icon(fallbackIcon, color: color, size: 24)),
            ),
          ),
          const SizedBox(height: 10),

          // Name
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: person != null
                    ? (isDark
                        ? Brand.darkTextPrimary
                        : AdminColors.text(context))
                    : AdminColors.warning,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          if (company != null && company.isNotEmpty) ...[
            const SizedBox(height: 2),
            Center(
              child: Text(
                company,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // Phone action
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone));
                  _snack('Phone number copied');
                },
                icon: Icon(Icons.phone_outlined, size: 14, color: color),
                label: Text(
                  phone,
                  style: TextStyle(fontSize: 12, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color.withAlpha(80)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Machine Card ──

  Widget _buildMachineCard(bool isDark) {
    final m = _schedule!['machine'] as Map<String, dynamic>?;
    if (m == null) return const SizedBox.shrink();
    final catalog = m['catalog'] as Map<String, dynamic>?;
    final imageUrl = catalog?['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return _card(
      isDark,
      label: 'Machine',
      icon: Icons.precision_manufacturing_outlined,
      children: [
        Row(
          children: [
            // Machine thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(Brand.r(10)),
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _machineIconBox(),
                    )
                  : _machineIconBox(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    catalog?['machine_name'] as String? ?? 'Unknown Machine',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : AdminColors.text(context),
                    ),
                  ),
                  if (catalog?['model_number'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Model: ${catalog!['model_number']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : AdminColors.textSub(context),
                      ),
                    ),
                  ],
                  if (m['serial_number'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'S/N: ${m['serial_number']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : AdminColors.textHint(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _machineIconBox() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withAlpha(26),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
        child: const Icon(
          Icons.precision_manufacturing,
          size: 28,
          color: Color(0xFF8B5CF6),
        ),
      );

  // ── Location Card ──

  Widget _buildLocationCard(bool isDark) {
    return _card(
      isDark,
      label: 'Service Location',
      icon: Icons.location_on_outlined,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on,
              size: 16,
              color: AdminColors.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _schedule!['service_location'] as String? ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : AdminColors.text(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Ticket Card ──

  Widget _buildTicketCard(bool isDark) {
    final t = _schedule!['ticket'] as Map<String, dynamic>?;
    if (t == null) return const SizedBox.shrink();

    return _card(
      isDark,
      label: 'Linked Ticket',
      icon: Icons.confirmation_number_outlined,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(20),
                borderRadius: BorderRadius.circular(Brand.r(8)),
              ),
              child: Text(
                '#${t['ticket_number'] ?? ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Brand.royalBlue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t['subject'] as String? ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : AdminColors.text(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Notes Card ──

  Widget _buildNotesCard(bool isDark) {
    final s = _schedule!;
    final adminNotes = s['admin_notes'] as String? ?? '';
    final customerNotes = s['customer_notes'] as String? ?? '';
    final engineerNotes = s['engineer_notes'] as String? ?? '';

    return _card(
      isDark,
      label: 'Notes',
      icon: Icons.notes_outlined,
      children: [
        if (adminNotes.isEmpty &&
            customerNotes.isEmpty &&
            engineerNotes.isEmpty)
          Text(
            'No notes added',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          )
        else ...[
          if (adminNotes.isNotEmpty)
            _noteItem(
              'Admin',
              adminNotes,
              Icons.admin_panel_settings,
              Brand.royalBlue,
              isDark,
            ),
          if (adminNotes.isNotEmpty && customerNotes.isNotEmpty)
            const SizedBox(height: 10),
          if (customerNotes.isNotEmpty)
            _noteItem(
              'Customer',
              customerNotes,
              Icons.person_outline,
              Brand.lightGreen,
              isDark,
            ),
          if (customerNotes.isNotEmpty && engineerNotes.isNotEmpty)
            const SizedBox(height: 10),
          if (engineerNotes.isNotEmpty)
            _noteItem(
              'Engineer',
              engineerNotes,
              Icons.engineering_outlined,
              const Color(0xFF14B8A6),
              isDark,
            ),
        ],
      ],
    );
  }

  Widget _noteItem(
    String label,
    String text,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(Brand.r(10)),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSub(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Service Report Card ──

  Widget _buildServiceReportCard(bool isDark) {
    final s = _schedule!;
    final report = s['service_report'] as String? ?? '';
    final rating = s['customer_rating'] as int?;
    final feedback = s['customer_feedback'] as String? ?? '';

    if (report.isEmpty && rating == null && feedback.isEmpty) {
      return const SizedBox.shrink();
    }

    return _card(
      isDark,
      label: 'Service Report',
      icon: Icons.assignment_turned_in_outlined,
      children: [
        if (rating != null) ...[
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$rating / 5',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : AdminColors.text(context),
                ),
              ),
            ],
          ),
          if (report.isNotEmpty || feedback.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (report.isNotEmpty) ...[
          Text(
            'Report',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
          if (feedback.isNotEmpty) const SizedBox(height: 10),
        ],
        if (feedback.isNotEmpty) ...[
          Text(
            'Customer Feedback',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '"$feedback"',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
        ],
      ],
    );
  }

  // ── Action Buttons ──

  Widget _buildActionButtons(bool isDark) {
    final status = _schedule!['status'] as String? ?? '';
    final actions = _getActions(status);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actions.map((a) {
        final isPrimary = a['primary'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 50,
            child: isPrimary
                ? FilledButton.icon(
                    onPressed: _acting
                        ? null
                        : () => _handleAction(a['action'] as String),
                    icon: _acting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(a['icon'] as IconData, size: 20),
                    label: Text(a['label'] as String),
                    style: FilledButton.styleFrom(
                      backgroundColor: a['color'] as Color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _acting
                        ? null
                        : () => _handleAction(a['action'] as String),
                    icon: Icon(
                      a['icon'] as IconData,
                      size: 20,
                      color: a['color'] as Color,
                    ),
                    label: Text(
                      a['label'] as String,
                      style: TextStyle(color: a['color'] as Color),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: (a['color'] as Color).withAlpha(128),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                      ),
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _getActions(String status) {
    switch (status) {
      case 'requested':
        return [
          {
            'label': 'Confirm & Schedule',
            'action': 'confirmed',
            'icon': Icons.check_circle,
            'color': const Color(0xFF6366F1),
            'primary': true,
          },
          {
            'label': 'Cancel Schedule',
            'action': 'cancel',
            'icon': Icons.cancel_outlined,
            'color': AdminColors.error,
            'primary': false,
          },
        ];
      case 'scheduled':
        return [
          {
            'label': 'Confirm Schedule',
            'action': 'confirmed',
            'icon': Icons.check_circle,
            'color': const Color(0xFF6366F1),
            'primary': true,
          },
          {
            'label': 'Reschedule',
            'action': 'reschedule',
            'icon': Icons.update,
            'color': const Color(0xFF8B5CF6),
            'primary': false,
          },
          {
            'label': 'Cancel Schedule',
            'action': 'cancel',
            'icon': Icons.cancel_outlined,
            'color': AdminColors.error,
            'primary': false,
          },
        ];
      case 'confirmed':
        return [
          {
            'label': 'Start Service',
            'action': 'in_progress',
            'icon': Icons.play_arrow_rounded,
            'color': const Color(0xFFF97316),
            'primary': true,
          },
          {
            'label': 'Reschedule',
            'action': 'reschedule',
            'icon': Icons.update,
            'color': const Color(0xFF8B5CF6),
            'primary': false,
          },
          {
            'label': 'Cancel Schedule',
            'action': 'cancel',
            'icon': Icons.cancel_outlined,
            'color': AdminColors.error,
            'primary': false,
          },
        ];
      case 'in_progress':
        return [
          {
            'label': 'Mark as Completed',
            'action': 'completed',
            'icon': Icons.check_rounded,
            'color': AdminColors.success,
            'primary': true,
          },
          {
            'label': 'Cancel Schedule',
            'action': 'cancel',
            'icon': Icons.cancel_outlined,
            'color': AdminColors.error,
            'primary': false,
          },
        ];
      default:
        return [];
    }
  }

  void _handleAction(String action) {
    switch (action) {
      case 'cancel':
        _showCancelDialog();
        break;
      case 'reschedule':
        _reschedule();
        break;
      default:
        _updateStatus(action);
    }
  }

  // ── Reusable Card ──

  Widget _card(
    bool isDark, {
    required List<Widget> children,
    String? label,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isDark
                        ? Brand.darkTextTertiary
                        : AdminColors.textHint(context),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark
                        ? Brand.darkTextTertiary
                        : AdminColors.textHint(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: isDark ? Brand.darkBorder : Brand.borderLight,
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color:
              isDark ? Brand.darkTextTertiary : AdminColors.textHint(context),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
            ),
          ),
        ),
      ],
    );
  }

  // ── Error / Not Found States ──

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color:
                isDark ? Brand.darkTextTertiary : AdminColors.textHint(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load schedule',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.royalBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 64,
            color:
                isDark ? Brand.darkTextTertiary : AdminColors.textHint(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Schedule not found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.royalBlue,
              side: const BorderSide(color: Brand.royalBlue),
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  // ── Shimmer ──

  Widget _buildShimmer(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        // Hero card shimmer
        ShimmerLoading(
          child: SkeletonBox(
            width: double.infinity,
            height: 160,
            radius: 20,
          ),
        ),
        SizedBox(height: 16),
        // Date/time card
        ShimmerLoading(
          child: SkeletonBox(
            width: double.infinity,
            height: 110,
            radius: 16,
          ),
        ),
        SizedBox(height: 12),
        // People row
        Row(
          children: [
            Expanded(
              child: ShimmerLoading(
                child: SkeletonBox(
                  width: double.infinity,
                  height: 140,
                  radius: 16,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ShimmerLoading(
                child: SkeletonBox(
                  width: double.infinity,
                  height: 140,
                  radius: 16,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Notes card
        ShimmerLoading(
          child: SkeletonBox(
            width: double.infinity,
            height: 100,
            radius: 16,
          ),
        ),
        SizedBox(height: 12),
        // Action buttons shimmer
        ShimmerLoading(
          child: SkeletonBox(
            width: double.infinity,
            height: 50,
            radius: 12,
          ),
        ),
      ],
    );
  }
}
