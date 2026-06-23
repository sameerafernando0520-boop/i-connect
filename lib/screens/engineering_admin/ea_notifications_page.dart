// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_notifications_page.dart
// EA Notifications — engineer admin receives ticket updates,
// dispatch events, leave approvals, schedule changes
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import 'ea_ticket_detail_page.dart';
import 'ea_leave_detail_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

// ── Notification type meta ─────────────────────────────────────
const _typeIcons = <String, IconData>{
  'ticket_update':        Icons.confirmation_number_rounded,
  'ticket_assigned':      Icons.assignment_ind_rounded,
  'engineer_dispatch':    Icons.engineering_rounded,
  'schedule_created':     Icons.calendar_today_rounded,
  'schedule_confirmed':   Icons.event_available_rounded,
  'schedule_cancelled':   Icons.event_busy_rounded,
  'schedule_reminder':    Icons.alarm_rounded,
  'leave_approved':       Icons.check_circle_rounded,
  'leave_rejected':       Icons.cancel_rounded,
  'leave_request':        Icons.beach_access_rounded,
  'new_message':          Icons.chat_bubble_rounded,
  'broadcast':            Icons.campaign_rounded,
  'system':               Icons.info_rounded,
};

const _typeColors = <String, Color>{
  'ticket_update':        Color(0xFF3B82F6),
  'ticket_assigned':      Color(0xFF6366F1),
  'engineer_dispatch':    Color(0xFF16A34A),
  'schedule_created':     Color(0xFF14B8A6),
  'schedule_confirmed':   Color(0xFF10B981),
  'schedule_cancelled':   Color(0xFFEF4444),
  'schedule_reminder':    Color(0xFFF59E0B),
  'leave_approved':       Color(0xFF16A34A),
  'leave_rejected':       Color(0xFFEF4444),
  'leave_request':        Color(0xFF8B5CF6),
  'new_message':          Color(0xFF3B82F6),
  'broadcast':            Color(0xFFF59E0B),
  'system':               Color(0xFF6B7280),
};

// ── Filter tabs ────────────────────────────────────────────────
const _filterTabs = <String, String>{
  'all':      'All',
  'unread':   'Unread',
  'tickets':  'Tickets',
  'schedule': 'Schedules',
  'leave':    'Leave',
};

class EaNotificationsPage extends StatefulWidget {
  const EaNotificationsPage({super.key});

  @override
  State<EaNotificationsPage> createState() => _EaNotificationsPageState();
}

class _EaNotificationsPageState extends State<EaNotificationsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  String _filter = 'all';
  bool _markingAll = false;

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) {
      SupabaseConfig.client.removeChannel(_channel!);
    }
    _debounce?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      final rows = await SupabaseConfig.client
          .from('notifications')
          .select(
            'id, title, body, message, type, notification_type, '
            'metadata, related_id, action_url, is_read, created_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(rows);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  bool _matchesFilter(Map<String, dynamic> n, String key) {
    final t = n['type'] as String? ?? '';
    switch (key) {
      case 'unread':   return n['is_read'] == false;
      case 'tickets':  return t == 'ticket_update' || t == 'ticket_assigned' ||
                              t == 'new_message'    || t == 'engineer_dispatch';
      case 'schedule': return t.startsWith('schedule');
      case 'leave':    return t.startsWith('leave');
      default:         return true; // 'all'
    }
  }

  int _countForFilter(String key) =>
      key == 'all' ? _all.length : _all.where((n) => _matchesFilter(n, key)).length;

  void _applyFilter() {
    _filtered = _filter == 'all'
        ? List.from(_all)
        : _all.where((n) => _matchesFilter(n, _filter)).toList();
  }

  // ── Realtime ──────────────────────────────────────────────────

  void _subscribeRealtime() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    void debounceReload(_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _load();
      });
    }

    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: userId,
    );

    _channel = SupabaseConfig.client
        .channel('ea_notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: filter,
          callback: debounceReload,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: filter,
          callback: debounceReload,
        )
        .subscribe();
  }

  // ── Mark as read ──────────────────────────────────────────────

  Future<void> _markRead(String id) async {
    // Optimistic local update
    final idx = _all.indexWhere((n) => n['id'] == id);
    if (idx != -1 && _all[idx]['is_read'] == false) {
      setState(() {
        final updated = Map<String, dynamic>.from(_all[idx]);
        updated['is_read'] = true;
        _all[idx] = updated;
        _applyFilter();
      });
      try {
        await SupabaseConfig.client
            .from('notifications')
            .update({'is_read': true})
            .eq('id', id);
      } catch (_) {
        // Revert on failure
        if (!mounted) return;
        setState(() {
          final reverted = Map<String, dynamic>.from(_all[idx]);
          reverted['is_read'] = false;
          _all[idx] = reverted;
          _applyFilter();
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final unread = _all.where((n) => n['is_read'] == false).toList();
    if (unread.isEmpty) return;

    setState(() => _markingAll = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      if (!mounted) return;
      setState(() {
        _all = _all.map((n) {
          final updated = Map<String, dynamic>.from(n);
          updated['is_read'] = true;
          return updated;
        }).toList();
        _applyFilter();
        _markingAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark all read: $e'),
          backgroundColor: AdminColors.error,
        ),
      );
    }
  }

  // ── Tap navigation ────────────────────────────────────────────

  void _handleTap(Map<String, dynamic> notification) {
    _markRead(notification['id'] as String);

    final type = notification['type'] as String? ?? '';
    final metadata = notification['metadata'] as Map<String, dynamic>?;
    final relatedId = notification['related_id'] as String?;

    // Ticket-related → navigate to ticket detail
    if (type == 'ticket_update' ||
        type == 'ticket_assigned' ||
        type == 'new_message' ||
        type == 'engineer_dispatch') {
      final ticketId = metadata?['ticket_id'] as String? ?? relatedId;
      if (ticketId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EaTicketDetailPage(ticketId: ticketId),
          ),
        );
        return;
      }
    }

    // Leave-related → navigate to leave detail
    if (type == 'leave_approved' ||
        type == 'leave_rejected' ||
        type == 'leave_request') {
      final leaveId = metadata?['leave_id'] as String? ?? relatedId;
      if (leaveId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EaLeaveDetailPage(leaveId: leaveId),
          ),
        );
        return;
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  int get _unreadCount => _all.where((n) => n['is_read'] == false).length;

  Color _colorForType(String? type) =>
      _typeColors[type ?? 'system'] ?? const Color(0xFF6B7280);

  IconData _iconForType(String? type) =>
      _typeIcons[type ?? 'system'] ?? Icons.notifications_rounded;

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    final dt = DateTime.tryParse(isoStr);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unread = _unreadCount;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: Column(
        children: [
          DsPageHeader(
            accent: HeroAccent.emerald,
            title: "Notifications",
            subtitle: unread > 0 ? "$unread unread" : null,
            actions: [
              if (unread > 0 && !_markingAll)
                TextButton(
                  onPressed: _markAllRead,
                  child: const Text("Mark all read",
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              DsHeroAction(Icons.refresh_rounded, _load),
            ],
          ),
          _buildFilterTabs(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  // ── Filter tabs ───────────────────────────────────────────────

  Widget _buildFilterTabs(bool isDark) {
    return Container(
      height: 48,
      color: Brand.surface(isDark),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: _filterTabs.entries.map((entry) {
          final key = entry.key;
          final label = entry.value;
          final active = _filter == key;
          final count = _countForFilter(key);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('$label${count > 0 ? ' ($count)' : ''}'),
              selected: active,
              onSelected: (_) => setState(() {
                _filter = key;
                _applyFilter();
              }),
              selectedColor: _eaAccent.withAlpha(30),
              checkmarkColor: _eaAccent,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? _eaAccent : AdminColors.textSub(context),
              ),
              side: BorderSide(
                color: active ? _eaAccent : AdminColors.border(context),
              ),
              backgroundColor: AdminColors.card(context),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────

  Widget _buildBody(bool isDark) {
    if (_loading) return _buildShimmer(isDark);
    if (_error != null) return _buildError();
    if (_filtered.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      color: _eaAccent,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final n = _filtered[i];
          final isFirst = i == 0;
          final showDateSeparator = isFirst ||
              !_sameDay(
                DateTime.tryParse(_filtered[i - 1]['created_at'] as String? ?? ''),
                DateTime.tryParse(n['created_at'] as String? ?? ''),
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDateSeparator) _buildDateSeparator(n['created_at'] as String?, isDark),
              _NotificationTile(
                notification: n,
                color: _colorForType(n['type'] as String?),
                icon: _iconForType(n['type'] as String?),
                timeLabel: _timeAgo(n['created_at'] as String?),
                onTap: () => _handleTap(n),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  Widget _buildDateSeparator(String? isoStr, bool isDark) {
    if (isoStr == null) return const SizedBox.shrink();
    final dt = DateTime.tryParse(isoStr)?.toLocal();
    if (dt == null) return const SizedBox.shrink();
    final now = DateTime.now();
    String label;
    if (_sameDay(dt, now)) {
      label = 'Today';
    } else if (_sameDay(dt, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AdminColors.textHint(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _monthName(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];

  // ── Shimmer ───────────────────────────────────────────────────

  Widget _buildShimmer(bool isDark) {
    final base = Brand.surface(isDark);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 8,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 76,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(Brand.r(14)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkBorderLight
                    : Brand.borderLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight
                          : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(6)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 160,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight
                          : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  // ── Error / empty ─────────────────────────────────────────────

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AdminColors.error, size: 44),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminColors.textSub(context)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: _eaAccent),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_off_outlined,
          size: 56,
          color: AdminColors.textHint(context),
        ),
        const SizedBox(height: 12),
        Text(
          _filter == 'unread'
              ? 'All caught up!'
              : 'No notifications',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AdminColors.textSub(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _filter == 'unread'
              ? 'You have no unread notifications'
              : 'Notifications will appear here',
          style: TextStyle(fontSize: 13, color: AdminColors.textHint(context)),
        ),
      ],
    ),
  );
}

// ── Notification Tile ─────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final Color color;
  final IconData icon;
  final String timeLabel;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.color,
    required this.icon,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = notification['is_read'] as bool? ?? true;
    final title = notification['title'] as String? ?? '';
    final body = notification['body'] as String? ??
        notification['message'] as String? ?? '';

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isRead
              ? (Brand.surface(isDark))
              : (isDark
                  ? color.withAlpha(20)
                  : color.withAlpha(12)),
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: Border.all(
            color: isRead
                ? (isDark ? Brand.darkBorder : Brand.borderLight)
                : color.withAlpha(60),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AdminColors.text(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: AdminColors.textSub(context),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Unread dot
              if (!isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
