// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_ticket_detail_page.dart
// EA Ticket Detail — Full ticket view for Engineering Admin
// Sections: status, customer, machine, engineer, chat shortcut,
//           activity timeline, admin notes, dispatch history
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import 'ea_ticket_chat_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaTicketDetailPage extends StatefulWidget {
  final String ticketId;

  const EaTicketDetailPage({super.key, required this.ticketId});

  @override
  State<EaTicketDetailPage> createState() => _EaTicketDetailPageState();
}

class _EaTicketDetailPageState extends State<EaTicketDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _dispatchHistory = [];

  final TextEditingController _notesCtrl = TextEditingController();
  bool _savingNotes = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        // Ticket full detail
        SupabaseConfig.client
            .from('service_tickets')
            .select('''
              id, ticket_number, subject, description, status, priority,
              created_at, updated_at, dispatched_at, dispatched_by,
              dispatch_notes, offer_expires_at,
              user_id, assigned_to,
              customer:users!user_id(id, full_name, phone_number, profile_photo, email),
              engineer:users!assigned_to(id, full_name, profile_photo, phone_number),
              machine:customer_machines(
                id, machine_nickname, serial_number, purchase_date,
                machine_catalog(machine_name, category, brand)
              ),
              dispatcher:users!dispatched_by(id, full_name)
            ''')
            .eq('id', widget.ticketId)
            .maybeSingle(),

        // Activities — ticket_activities columns are activity_type/description,
        // and the FK to users is actor_id (not user_id).
        SupabaseConfig.client
            .from('ticket_activities')
            .select(
              'id, activity_type, description, created_at, '
              'user:users!actor_id(full_name, role)',
            )
            .eq('ticket_id', widget.ticketId)
            .order('created_at', ascending: false)
            .limit(20),

        // Dispatch offers history
        SupabaseConfig.client
            .from('job_dispatch_offers')
            .select('''
              id, offer_mode, status, offer_note, offered_at, expires_at,
              responded_at, response_note,
              engineer:users!engineer_id(id, full_name, profile_photo),
              offered_by_user:users!offered_by(id, full_name)
            ''')
            .eq('ticket_id', widget.ticketId)
            .order('offered_at', ascending: false),
      ]);

      if (!mounted) return;

      final ticketData = results[0] as Map<String, dynamic>?;
      if (ticketData == null) {
        setState(() {
          _error = 'Ticket not found';
          _loading = false;
        });
        return;
      }

      _notesCtrl.text = ticketData['dispatch_notes'] as String? ?? '';

      setState(() {
        _ticket = ticketData;
        _activities = List<Map<String, dynamic>>.from(results[1] as List);
        _dispatchHistory =
            List<Map<String, dynamic>>.from(results[2] as List);
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

  Future<void> _saveNotes() async {
    setState(() => _savingNotes = true);
    try {
      await SupabaseConfig.client
          .from('service_tickets')
          .update({'dispatch_notes': _notesCtrl.text.trim()}).eq(
              'id', widget.ticketId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Notes saved'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
          margin: const EdgeInsets.all(12),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  // ── Delete (soft-archive) ─────────────────────────────────────

  Future<void> _confirmAndDelete() async {
    final t = _ticket;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete this ticket?'),
        content: Text(
          'Ticket ${t?['ticket_number'] ?? ''} will be removed from the '
          'lists. It can be restored later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      await SupabaseConfig.client.from('service_tickets').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': uid,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.ticketId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket deleted')),
      );
      Navigator.pop(context, true); // signal list to refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _ticket;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: t != null ? '${t['ticket_number'] ?? ''}' : 'Ticket Detail',
        accent: HeroAccent.emerald,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AdminColors.error),
            tooltip: 'Delete ticket',
            onPressed: _ticket == null ? null : _confirmAndDelete,
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : _error != null
              ? _buildError(context)
              : _buildBody(context, t!, isDark),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> t, bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── 1. Status + Priority ─────────────────────────────
          _SectionCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('Status & Priority', isDark: isDark),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _InfoChip(
                      label: _statusLabel(t['status'] as String? ?? ''),
                      color: AdminColors.statusColor(
                          t['status'] as String? ?? ''),
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      label: '${_capitalize(t['priority'] as String? ?? '')} Priority',
                      color: AdminColors.priorityColor(
                          t['priority'] as String? ?? ''),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _LabelValue(
                  label: 'Created',
                  value: _formatDate(t['created_at'] as String?),
                  isDark: isDark,
                ),
                _LabelValue(
                  label: 'Last updated',
                  value: _formatDate(t['updated_at'] as String?),
                  isDark: isDark,
                ),
                if (t['dispatched_at'] != null)
                  _LabelValue(
                    label: 'Dispatched',
                    value: _formatDate(t['dispatched_at'] as String?),
                    isDark: isDark,
                  ),
              ],
            ),
          ),

          // ── 2. Customer ─────────────────────────────────────
          if (t['customer'] != null)
            _SectionCard(
              isDark: isDark,
              child: _CustomerCard(
                  customer: t['customer'] as Map, isDark: isDark),
            ),

          // ── 3. Machine ──────────────────────────────────────
          if (t['machine'] != null)
            _SectionCard(
              isDark: isDark,
              child: _MachineCard(
                  machine: t['machine'] as Map, isDark: isDark),
            ),

          // ── 4. Assigned Engineer ─────────────────────────────
          _SectionCard(
            isDark: isDark,
            child: _EngineerSection(
              ticket: t,
              isDark: isDark,
              onOpenChat: () => _openChat(context, t),
            ),
          ),

          // ── 5. Chat shortcut ─────────────────────────────────
          _ChatShortcutButton(
            isDark: isDark,
            onTap: () => _openChat(context, t),
          ),

          // ── 6. Admin notes ───────────────────────────────────
          _SectionCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('Dispatch Notes', isDark: isDark,
                    icon: Icons.sticky_note_2_rounded),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 4,
                  style: TextStyle(
                    color: AdminColors.text(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Internal notes about dispatch decisions, customer details, access instructions...',
                    hintStyle:
                        TextStyle(color: AdminColors.textHint(context)),
                    filled: true,
                    fillColor: isDark
                        ? Brand.darkCardElevated
                        : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _savingNotes ? null : _saveNotes,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _eaAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(10))),
                    ),
                    child: _savingNotes
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Text('Save Notes'),
                  ),
                ),
              ],
            ),
          ),

          // ── 7. Activity timeline ─────────────────────────────
          if (_activities.isNotEmpty)
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle('Activity Timeline', isDark: isDark,
                      icon: Icons.history_rounded),
                  const SizedBox(height: 8),
                  ..._activities.map((a) => _ActivityItem(
                        activity: a,
                        isDark: isDark,
                      )),
                ],
              ),
            ),

          // ── 8. Dispatch history ──────────────────────────────
          if (_dispatchHistory.isNotEmpty)
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle('Dispatch History', isDark: isDark,
                      icon: Icons.bolt_rounded),
                  const SizedBox(height: 8),
                  ..._dispatchHistory.map((d) => _DispatchHistoryItem(
                        offer: d,
                        isDark: isDark,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, Map<String, dynamic> t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EaTicketChatPage(
          ticketId: widget.ticketId,
          ticketTitle: t['subject'] as String? ?? 'Ticket',
        ),
      ),
    ).then((_) => _load());
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _statusLabel(String s) {
    switch (s) {
      case 'new':
        return 'New';
      case 'open':
        return 'Open';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'waiting_customer':
        return 'Waiting for Customer';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return s;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return TimeUtils.formatDateTime(dt);
    } catch (_) {
      return iso;
    }
  }

  Widget _buildShimmer(bool isDark) {
    final color =
        isDark ? Brand.darkCardElevated : const Color(0xFFE2E8F0);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        height: 120,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Brand.r(16)),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AdminColors.error),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Unknown error',
            style: TextStyle(color: AdminColors.textSub(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: _eaAccent),
            child: const Text('Retry',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  final IconData? icon;

  const _SectionTitle(this.title, {required this.isDark, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: _eaAccent),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: TextStyle(
            color: AdminColors.text(context),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _LabelValue(
      {required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                  color: AdminColors.textHint(context), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AdminColors.text(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(Brand.r(8)),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Map customer;
  final bool isDark;

  const _CustomerCard({required this.customer, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final name = customer['full_name'] as String? ?? 'Customer';
    final phone = customer['phone_number'] as String? ?? '—';
    final email = customer['email'] as String? ?? '—';
    final photo = customer['profile_photo'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Customer', isDark: isDark, icon: Icons.person_rounded),
        const SizedBox(height: 12),
        Row(
          children: [
            _SmallAvatar(photoUrl: photo, name: name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: AdminColors.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: TextStyle(
                        color: AdminColors.textSub(context), fontSize: 13),
                  ),
                  Text(
                    email,
                    style: TextStyle(
                        color: AdminColors.textSub(context), fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Machine card ──────────────────────────────────────────────────────────────

class _MachineCard extends StatelessWidget {
  final Map machine;
  final bool isDark;

  const _MachineCard({required this.machine, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final nickname = machine['machine_nickname'] as String? ?? 'Machine';
    final serial = machine['serial_number'] as String? ?? '—';
    final purchase = machine['purchase_date'] as String?;
    final catalog = machine['machine_catalog'] as Map?;
    final modelName = catalog?['machine_name'] as String? ?? '—';
    final category = catalog?['category'] as String? ?? '—';
    final brand = catalog?['brand'] as String? ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Machine', isDark: isDark,
            icon: Icons.precision_manufacturing_rounded),
        const SizedBox(height: 12),
        _LabelValue(label: 'Nickname', value: nickname, isDark: isDark),
        _LabelValue(label: 'Model', value: modelName, isDark: isDark),
        _LabelValue(label: 'Brand', value: brand, isDark: isDark),
        _LabelValue(label: 'Category', value: category, isDark: isDark),
        _LabelValue(label: 'Serial No.', value: serial, isDark: isDark),
        if (purchase != null)
          _LabelValue(
            label: 'Purchased',
            value: purchase,
            isDark: isDark,
          ),
      ],
    );
  }
}

// ── Engineer section ──────────────────────────────────────────────────────────

class _EngineerSection extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool isDark;
  final VoidCallback onOpenChat;

  const _EngineerSection({
    required this.ticket,
    required this.isDark,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final engineer = ticket['engineer'] as Map?;
    final isAssigned = engineer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Assigned Engineer', isDark: isDark,
            icon: Icons.engineering_rounded),
        const SizedBox(height: 12),
        if (!isAssigned) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StatusColors.danger.withAlpha(12),
              borderRadius: BorderRadius.circular(Brand.r(12)),
              border: Border.all(
                  color: StatusColors.danger.withAlpha(40)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: StatusColors.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No engineer assigned yet. Open chat to dispatch.',
                    style: TextStyle(
                      color: AdminColors.text(context),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpenChat,
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Dispatch Engineer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
              ),
            ),
          ),
        ] else ...[
          Row(
            children: [
              _SmallAvatar(
                photoUrl: engineer['profile_photo'] as String?,
                name: engineer['full_name'] as String? ?? '?',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engineer['full_name'] as String? ?? 'Engineer',
                      style: TextStyle(
                        color: AdminColors.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (engineer['phone_number'] != null)
                      Text(
                        engineer['phone_number'] as String,
                        style: TextStyle(
                            color: AdminColors.textSub(context),
                            fontSize: 13),
                      ),
                    if (ticket['dispatched_at'] != null)
                      Text(
                        'Dispatched ${_ago(ticket['dispatched_at'] as String)}',
                        style: TextStyle(
                            color: AdminColors.textHint(context),
                            fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _ago(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return TimeUtils.getTimeAgo(dt);
    } catch (_) {
      return '';
    }
  }
}

// ── Chat shortcut button ─────────────────────────────────────────────────────

class _ChatShortcutButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _ChatShortcutButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_eaAccent, Brand.royalBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(Brand.r(16)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'View full conversation + dispatch controls',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Activity item ─────────────────────────────────────────────────────────────

class _ActivityItem extends StatelessWidget {
  final Map<String, dynamic> activity;
  final bool isDark;

  const _ActivityItem({required this.activity, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Renamed activity_type → action / description → note when read so the
    // existing UI builders keep working with the same local variables.
    final action = activity['activity_type'] as String? ?? '';
    final note = activity['description'] as String? ?? '';
    final createdAt = activity['created_at'] as String?;
    final user = activity['user'] as Map?;
    final userName = user?['full_name'] as String? ?? 'User';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _eaAccent,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: AdminColors.border(context),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionLabel(action),
                  style: TextStyle(
                    color: AdminColors.text(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (note.isNotEmpty)
                  Text(
                    note,
                    style: TextStyle(
                        color: AdminColors.textSub(context),
                        fontSize: 12),
                  ),
                Text(
                  '$userName · ${_formatAgo(createdAt)}',
                  style: TextStyle(
                      color: AdminColors.textHint(context), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'created':
        return 'Ticket created';
      case 'status_changed':
        return 'Status updated';
      case 'assigned':
        return 'Engineer assigned';
      case 'note_added':
        return 'Note added';
      case 'resolved':
        return 'Ticket resolved';
      case 'closed':
        return 'Ticket closed';
      default:
        return action.replaceAll('_', ' ');
    }
  }

  String _formatAgo(String? iso) {
    if (iso == null) return '';
    try {
      return TimeUtils.getTimeAgo(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ── Dispatch history item ─────────────────────────────────────────────────────

class _DispatchHistoryItem extends StatelessWidget {
  final Map<String, dynamic> offer;
  final bool isDark;

  const _DispatchHistoryItem({required this.offer, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final engineer =
        (offer['engineer'] as Map?)?['full_name'] as String? ?? 'Engineer';
    final offeredBy = (offer['offered_by_user'] as Map?)?['full_name']
        as String? ??
        'Admin';
    final mode = offer['offer_mode'] as String? ?? 'direct';
    final status = offer['status'] as String? ?? 'pending';
    final offeredAt = offer['offered_at'] as String?;
    final responseNote = offer['response_note'] as String? ?? '';

    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        borderRadius: BorderRadius.circular(Brand.r(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(Brand.r(8)),
            ),
            child: Icon(_modeIcon(mode), color: statusColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        engineer,
                        style: TextStyle(
                          color: AdminColors.text(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(Brand.r(6)),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_modeLabel(mode)} by $offeredBy · ${_formatAgo(offeredAt)}',
                  style: TextStyle(
                      color: AdminColors.textSub(context), fontSize: 11),
                ),
                if (responseNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '"$responseNote"',
                      style: TextStyle(
                          color: AdminColors.textHint(context),
                          fontSize: 11,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return AdminColors.success;
      case 'declined':
        return AdminColors.error;
      case 'expired':
        return AdminColors.warning;
      case 'cancelled':
        return AdminColors.info;
      default:
        return Brand.subtleLight;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s;
    }
  }

  String _modeLabel(String m) {
    switch (m) {
      case 'direct':
        return 'Direct assign';
      case 'open_offer':
        return 'Job offered';
      case 'broadcast':
        return 'Broadcast';
      default:
        return m;
    }
  }

  IconData _modeIcon(String m) {
    switch (m) {
      case 'direct':
        return Icons.person_pin_rounded;
      case 'open_offer':
        return Icons.local_offer_rounded;
      case 'broadcast':
        return Icons.broadcast_on_personal_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  String _formatAgo(String? iso) {
    if (iso == null) return '';
    try {
      return TimeUtils.getTimeAgo(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ── Small avatar ─────────────────────────────────────────────────────────────

class _SmallAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _SmallAvatar({required this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join()
        : '?';

    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: 44,
                height: 44,
                errorWidget: (_, __, ___) =>
                    _initials(initials),
              )
            : _initials(initials),
      ),
    );
  }

  Widget _initials(String i) => Container(
        color: _eaAccent.withAlpha(20),
        child: Center(
          child: Text(
            i,
            style: const TextStyle(
              color: _eaAccent,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      );
}
