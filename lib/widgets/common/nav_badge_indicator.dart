// lib/widgets/common/nav_badge_indicator.dart
//
// Self-subscribing badge count for nav icons.
//
// Owns its own count + Postgres-changes subscription so the badge
// stays in sync without depending on a parent dashboard reload.
//
// API: pass a `builder` that renders the icon however the call site
// wants — the widget injects only the live `count`. Each existing
// nav button keeps its own visual styling (colour/gradient/size).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

enum NavBadgeType {
  /// Unread chat messages on active service tickets (ticket_type != 'inquiry').
  tickets,

  /// Unread chat messages on active inquiry tickets (ticket_type = 'inquiry').
  inquiries,

  /// Unread notification rows for the current user.
  notifications,
}

class NavBadgeIndicator extends StatefulWidget {
  final NavBadgeType badgeType;
  final Widget Function(BuildContext context, int count) builder;

  const NavBadgeIndicator({
    super.key,
    required this.badgeType,
    required this.builder,
  });

  @override
  State<NavBadgeIndicator> createState() => _NavBadgeIndicatorState();
}

class _NavBadgeIndicatorState extends State<NavBadgeIndicator> {
  int _count = 0;
  RealtimeChannel? _channel;
  RealtimeChannel? _statusChannel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final ch in [_channel, _statusChannel]) {
      if (ch != null) {
        try {
          SupabaseConfig.client.removeChannel(ch);
        } catch (_) {}
      }
    }
    super.dispose();
  }

  Future<void> _loadCount() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      int count = 0;
      switch (widget.badgeType) {
        case NavBadgeType.tickets:
          count = await _countUnreadMessages(
            userId: userId,
            ticketTypeFilter: 'neq_inquiry',
          );
          break;
        case NavBadgeType.inquiries:
          count = await _countUnreadMessages(
            userId: userId,
            ticketTypeFilter: 'eq_inquiry',
          );
          break;
        case NavBadgeType.notifications:
          final res = await SupabaseConfig.client
              .from('notifications')
              .count(CountOption.exact)
              .eq('user_id', userId)
              .eq('is_read', false);
          count = res;
          break;
      }
      if (!mounted) return;
      if (count != _count) setState(() => _count = count);
    } catch (e) {
      debugPrint('NavBadgeIndicator(${widget.badgeType.name}) load failed: $e');
    }
  }

  /// Count unread chat_messages on active tickets, filtered by type.
  Future<int> _countUnreadMessages({
    required String userId,
    required String ticketTypeFilter,
  }) async {
    // Step 1: fetch IDs of active tickets of the right type.
    var query = SupabaseConfig.client
        .from('service_tickets')
        .select('id')
        .eq('is_deleted', false)
        .inFilter('status', const [
      'new',
      'open',
      'assigned',
      'in_progress',
      'waiting_customer',
    ]);

    if (ticketTypeFilter == 'eq_inquiry') {
      query = query.eq('ticket_type', 'inquiry');
    } else {
      query = query.neq('ticket_type', 'inquiry');
    }

    final rows = await query;
    final ids =
        (rows as List).map((r) => r['id'] as String).toList(growable: false);
    if (ids.isEmpty) return 0;

    // Step 2: count unread chat_messages NOT sent by this user.
    final res = await SupabaseConfig.client
        .from('chat_messages')
        .count(CountOption.exact)
        .filter('read_at', 'is', null)
        .neq('sender_id', userId)
        .inFilter('ticket_id', ids);
    return res;
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadCount();
    });
  }

  void _subscribe() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    final typeName = widget.badgeType.name; // 'tickets', 'inquiries', etc.

    // Listen to chat_messages or notifications table changes.
    final table = switch (widget.badgeType) {
      NavBadgeType.tickets => 'chat_messages',
      NavBadgeType.inquiries => 'chat_messages',
      NavBadgeType.notifications => 'notifications',
    };

    _channel = SupabaseConfig.client
        .channel('nav_badge_${typeName}_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => _scheduleReload(),
        )
        .subscribe();

    // Tickets & inquiries also react to service_tickets status changes
    // (resolved/closed/completed drops them out of active scope).
    if (widget.badgeType == NavBadgeType.tickets ||
        widget.badgeType == NavBadgeType.inquiries) {
      _statusChannel = SupabaseConfig.client
          .channel('nav_badge_${typeName}_status_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'service_tickets',
            callback: (_) => _scheduleReload(),
          )
          .subscribe();
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _count);
}
