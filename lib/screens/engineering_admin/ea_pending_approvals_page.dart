// lib/screens/engineering_admin/ea_pending_approvals_page.dart
// v24 — Schedule + installation approval queue
//
// Surfaces engineer-proposed service_schedules (status='pending_approval')
// so an EA or admin can approve / reject.  On approve:
//   • status flips to 'scheduled'
//   • customer gets notified
//   • engineer gets notified
//   • notification rows tagged with metadata.type='schedule_approved'
//
// On reject:
//   • status flips to 'cancelled'
//   • engineer notified with metadata.type='schedule_rejected'
//   • customer NOT notified (per spec — approvals invisible to customer)

import 'package:flutter/material.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

const Color _eaAccent = Color(0xFF16A34A);
const Color _eaRed = Color(0xFFEF4444);

class EaPendingApprovalsPage extends StatefulWidget {
  const EaPendingApprovalsPage({super.key});

  @override
  State<EaPendingApprovalsPage> createState() => _EaPendingApprovalsPageState();
}

class _EaPendingApprovalsPageState extends State<EaPendingApprovalsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _busy = {};

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
      final rows = await SupabaseConfig.client
          .from('service_schedules')
          .select('''
            id, title, schedule_type, scheduled_date, scheduled_time,
            estimated_duration, service_location, description, engineer_notes,
            created_at,
            customer:users!customer_id(id, full_name, phone_number),
            engineer:users!engineer_id(id, full_name, profile_photo),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name)
            )
          ''')
          .eq('status', 'pending_approval')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows as List);
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

  Future<void> _approve(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    final approverId = SupabaseConfig.client.auth.currentUser?.id;

    try {
      await SupabaseConfig.client
          .from('service_schedules')
          .update({
            'status': 'scheduled',
            'approved_by': approverId,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);

      // Notify customer (visible message — the customer should NOT see the
      // word "approved" or know it was approval-gated).
      final customer = item['customer'] as Map<String, dynamic>?;
      final engineer = item['engineer'] as Map<String, dynamic>?;
      final now = DateTime.now().toUtc().toIso8601String();
      final notifications = <Map<String, dynamic>>[];
      if (customer != null) {
        notifications.add({
          'user_id': customer['id'],
          'title': 'New service scheduled',
          'body':
              '${item['title'] ?? 'Service'} • ${_fmt(item['scheduled_date'], item['scheduled_time'])}',
          'type': 'schedule_created',
          'is_read': false,
          'created_at': now,
          'metadata': {
            'type': 'schedule_created',
            'schedule_id': id,
          },
        });
      }
      if (engineer != null) {
        notifications.add({
          'user_id': engineer['id'],
          'title': 'Schedule approved',
          'body':
              'Your schedule "${item['title']}" was approved and customer notified.',
          'type': 'system',
          'is_read': false,
          'created_at': now,
          'metadata': {
            'type': 'schedule_approved',
            'schedule_id': id,
          },
        });
      }
      if (notifications.isNotEmpty) {
        await SupabaseConfig.client
            .from('notifications')
            .insert(notifications);
      }
      // Best-effort push.
      try {
        await SupabaseConfig.client.functions.invoke('send-push', body: {
          'title': 'Service schedule',
          'body': item['title'] ?? 'A new service has been scheduled',
          'user_ids':
              notifications.map((n) => n['user_id'] as String).toList(),
        });
      } catch (_) {}

      if (!mounted) return;
      _snack('Approved & customer notified', _eaAccent);
      setState(() {
        _items.removeWhere((x) => x['id'] == id);
        _busy.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      _snack('Approve failed: $e', _eaRed);
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (_busy.contains(id)) return;

    final reason = await _askReason();
    if (reason == null) return;

    setState(() => _busy.add(id));
    final approverId = SupabaseConfig.client.auth.currentUser?.id;
    try {
      await SupabaseConfig.client
          .from('service_schedules')
          .update({
            'status': 'cancelled',
            'approved_by': approverId,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
            'admin_notes': reason.isEmpty ? null : reason,
          })
          .eq('id', id);

      final engineer = item['engineer'] as Map<String, dynamic>?;
      if (engineer != null) {
        await SupabaseConfig.client.from('notifications').insert({
          'user_id': engineer['id'],
          'title': 'Schedule not approved',
          'body': reason.isEmpty
              ? 'Your schedule "${item['title']}" was not approved.'
              : 'Schedule "${item['title']}" rejected: $reason',
          'type': 'system',
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'metadata': {
            'type': 'schedule_rejected',
            'schedule_id': id,
          },
        });
      }

      if (!mounted) return;
      _snack('Rejected & engineer notified', _eaRed);
      setState(() {
        _items.removeWhere((x) => x['id'] == id);
        _busy.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      _snack('Reject failed: $e', _eaRed);
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: const Text('Reject schedule'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason for rejection (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: _eaRed),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: Column(children: [
        DsPageHeader(
          accent: HeroAccent.emerald,
          title: 'Pending Approvals',
          actions: [
            DsHeroAction(Icons.refresh_rounded, _load),
          ],
        ),
        Expanded(
          child: _loading
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : _error != null
              ? _errorView()
              : _items.isEmpty
                  ? _emptyView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _eaAccent,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _card(_items[i], isDark),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _emptyView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: AdminColors.textHint(context)),
            const SizedBox(height: 12),
            Text('No pending approvals',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textSub(context),
                )),
            const SizedBox(height: 4),
            Text('Engineer-created schedules will show here for review.',
                style:
                    TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: _eaRed),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AdminColors.textSub(context))),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _card(Map<String, dynamic> item, bool isDark) {
    final id = item['id'] as String;
    final customer = item['customer'] as Map<String, dynamic>?;
    final engineer = item['engineer'] as Map<String, dynamic>?;
    final machine = item['machine'] as Map<String, dynamic>?;
    final catalog = machine?['catalog'] as Map<String, dynamic>?;
    final title = item['title'] as String? ?? 'Untitled';
    final type = item['schedule_type'] as String? ?? '';
    final date = item['scheduled_date'] as String?;
    final time = item['scheduled_time'] as String?;
    final loc = item['service_location'] as String?;
    final notes = item['engineer_notes'] as String?;
    final busy = _busy.contains(id);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(
          color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _eaAccent.withAlpha(isDark ? 40 : 22),
                borderRadius: BorderRadius.circular(Brand.r(6)),
              ),
              child: Text(type.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _eaAccent,
                    letterSpacing: 0.5,
                  )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF0F172A),
                  )),
            ),
          ]),
          const SizedBox(height: 8),
          _meta(Icons.calendar_today_rounded, _fmt(date, time), isDark),
          if (loc != null && loc.isNotEmpty)
            _meta(Icons.location_on_rounded, loc, isDark),
          _meta(Icons.person_rounded, 'Customer: ${customer?['full_name'] ?? '—'}',
              isDark),
          _meta(Icons.engineering_rounded,
              'Engineer: ${engineer?['full_name'] ?? '—'}', isDark),
          if (catalog?['machine_name'] != null)
            _meta(Icons.precision_manufacturing_rounded,
                catalog!['machine_name'] as String, isDark),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminColors.bg(context),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: Text(notes,
                  style: TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSub(context),
                  )),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _reject(item),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _eaRed,
                  side: const BorderSide(color: _eaRed),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : () => _approve(item),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text('Approve'),
                style: FilledButton.styleFrom(
                  backgroundColor: _eaAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12))),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Icon(icon, size: 13, color: AdminColors.textSub(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: AdminColors.textSub(context),
              )),
        ),
      ]),
    );
  }

  String _fmt(dynamic date, dynamic time) {
    final d = date?.toString() ?? '';
    final t = time?.toString() ?? '';
    return [d, t].where((s) => s.isNotEmpty).join(' · ');
  }
}
