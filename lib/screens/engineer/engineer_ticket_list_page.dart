// lib/screens/engineer/engineer_ticket_list_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter,
         PostgresChangeFilterType;
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import 'engineer_ticket_detail_page.dart';

// ── Engineer accent (per handoff §26) ──
const Color _engAccent = Color(0xFF00B4D8);
const Color _engAccentDark = Color(0xFF0096B7);

class EngineerTicketListPage extends StatefulWidget {
  const EngineerTicketListPage({super.key});

  @override
  State<EngineerTicketListPage> createState() => _EngineerTicketListPageState();
}

class _EngineerTicketListPageState extends State<EngineerTicketListPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allTickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];

  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String _typeFilter = 'all';
  String _searchQuery = '';
  String _sortBy = 'updated'; // 'updated', 'created', 'priority'

  final _searchCtrl = TextEditingController();

  // Realtime subscription for live ticket updates
  RealtimeChannel? _ticketChannel;
  Timer? _realtimeDebounce;

  final _statusOptions = [
    'all',
    'open',
    'assigned',
    'in_progress',
    'waiting_customer',
    'resolved',
    'closed',
  ];
  final _priorityOptions = ['all', 'urgent', 'high', 'medium', 'low'];
  final _typeOptions = ['all', 'support', 'inquiry', 'order'];

  @override
  void initState() {
    super.initState();
    _loadTickets();
    _subscribeTickets();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _realtimeDebounce?.cancel();
    if (_ticketChannel != null) {
      SupabaseConfig.client.removeChannel(_ticketChannel!);
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  REALTIME
  // ═══════════════════════════════════════════════════════════

  void _subscribeTickets() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    _ticketChannel = SupabaseConfig.client
        .channel('eng_ticket_list_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_to',
            value: uid,
          ),
          callback: (_) => _debouncedReload(),
        )
        .subscribe();
  }

  void _debouncedReload() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _loadTickets();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return;

      final r = await SupabaseConfig.client.from('service_tickets').select('''
            id, ticket_number, subject, priority, status, ticket_type,
            created_at, updated_at,
            customer:users!service_tickets_user_id_fkey(
              full_name, company_name, phone_number
            ),
            customer_machine:customer_machines(
              serial_number,
              catalog_machine:machine_catalog(
                machine_name, model_number, category
              )
            )
          ''')
          .eq('assigned_to', uid)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _allTickets = List<Map<String, dynamic>>.from(r);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Engineer ticket list load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _filteredTickets = _allTickets.where((t) {
      final s = t['status'] as String? ?? '';
      final p = t['priority'] as String? ?? '';
      final tp = t['ticket_type'] as String? ?? '';
      final sub = (t['subject'] as String? ?? '').toLowerCase();
      final tn = (t['ticket_number'] as String? ?? '').toLowerCase();
      final customer = t['customer'] as Map<String, dynamic>?;
      final cn = (customer?['full_name'] as String? ?? '').toLowerCase();
      final comp =
          (customer?['company_name'] as String? ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();

      if (_statusFilter != 'all' && s != _statusFilter) return false;
      if (_priorityFilter != 'all' && p != _priorityFilter) {
        return false;
      }
      if (_typeFilter != 'all' && tp != _typeFilter) return false;
      if (q.isNotEmpty &&
          !sub.contains(q) &&
          !cn.contains(q) &&
          !tn.contains(q) &&
          !comp.contains(q)) {
        return false;
      }
      return true;
    }).toList();

    // Apply sort
    _filteredTickets.sort((a, b) {
      switch (_sortBy) {
        case 'created':
          final ac = a['created_at'] as String? ?? '';
          final bc = b['created_at'] as String? ?? '';
          return bc.compareTo(ac);
        case 'priority':
          const pOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
          final ap = pOrder[a['priority']] ?? 4;
          final bp = pOrder[b['priority']] ?? 4;
          if (ap != bp) return ap.compareTo(bp);
          final au = a['updated_at'] as String? ?? '';
          final bu = b['updated_at'] as String? ?? '';
          return bu.compareTo(au);
        default: // 'updated'
          final au = a['updated_at'] as String? ?? '';
          final bu = b['updated_at'] as String? ?? '';
          return bu.compareTo(au);
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'all';
      _priorityFilter = 'all';
      _typeFilter = 'all';
      _searchQuery = '';
      _searchCtrl.clear();
      _applyFilters();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  bool get _hasActiveFilters =>
      _statusFilter != 'all' ||
      _priorityFilter != 'all' ||
      _typeFilter != 'all' ||
      _searchQuery.isNotEmpty;

  /// Compact time label for card: "2m", "3h", "5d"
  String _compactTime(String? d) {
    if (d == null) return '';
    try {
      final diff = DateTime.now().difference(DateTime.parse(d));
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':
        return const Color(0xFFFF4757);
      case 'high':
        return const Color(0xFFFFB74D);
      case 'medium':
        return Brand.lightGreenBright;
      default:
        return Brand.darkTextSecondary;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Brand.darkIconActive;
      case 'assigned':
        return const Color(0xFF7986CB);
      case 'in_progress':
        return const Color(0xFFFFB74D);
      case 'waiting_customer':
        return const Color(0xFFCE93D8);
      case 'resolved':
        return Brand.lightGreenBright;
      case 'closed':
        return Brand.darkTextSecondary;
      default:
        return Brand.darkTextSecondary;
    }
  }

  void _navigateToDetail(String ticketId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EngineerTicketDetailPage(ticketId: ticketId),
      ),
    ).then((_) {
      if (mounted) _loadTickets();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(isDark),
          _buildSearchBar(isDark),
          _buildFilterChips(isDark),
          _buildResultCount(isDark),
          Expanded(
            child: _isLoading
                ? _buildSkeleton(isDark)
                : _filteredTickets.isEmpty
                    ? _buildEmptyState(isDark)
                    : RefreshIndicator(
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                        backgroundColor: isDark ? Brand.darkCard : Colors.white,
                        onRefresh: _loadTickets,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: _filteredTickets.length,
                          itemBuilder: (_, i) =>
                              _ticketCard(_filteredTickets[i], isDark),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [_engAccent, _engAccentDark],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'My Tickets',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  (isDark ? Brand.darkIconActive : _engAccent).withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_filteredTickets.length}/${_allTickets.length}',
              style: TextStyle(
                color: isDark ? Brand.darkIconActive : _engAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  SEARCH BAR
  // ═══════════════════════════════════════════════════════════

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(13),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() {
            _searchQuery = v;
            _applyFilters();
          }),
          style: TextStyle(
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Search by ticket #, subject, customer...',
            hintStyle: TextStyle(
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _searchQuery = '';
                      _applyFilters();
                    }),
                  )
                : null,
            enabledBorder: InputBorder.none,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark ? Brand.darkIconActive : _engAccent,
                width: 1.5,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  FILTER CHIPS
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilterChips(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRow(
            'Status',
            _statusOptions,
            _statusFilter,
            (v) => setState(() {
              _statusFilter = v;
              _applyFilters();
            }),
            isDark,
          ),
          const SizedBox(height: 8),
          _chipRow(
            'Priority',
            _priorityOptions,
            _priorityFilter,
            (v) => setState(() {
              _priorityFilter = v;
              _applyFilters();
            }),
            isDark,
          ),
          const SizedBox(height: 8),
          _chipRow(
            'Type',
            _typeOptions,
            _typeFilter,
            (v) => setState(() {
              _typeFilter = v;
              _applyFilters();
            }),
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _chipRow(
    String label,
    List<String> opts,
    String selected,
    ValueChanged<String> onSelect,
    bool isDark,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const SizedBox(width: 10),
          ...opts.map((o) {
            final isSel = selected == o;
            final chipInfo = _chipStyle(o, isDark);
            final Color c = chipInfo.$1;
            final IconData? icon = chipInfo.$2;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onSelect(o),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel
                        ? (o == 'all'
                            ? (isDark ? Brand.darkIconActive : _engAccent)
                                .withAlpha(38)
                            : c.withAlpha(38))
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel
                          ? (o == 'all'
                                  ? (isDark ? Brand.darkIconActive : _engAccent)
                                  : c)
                              .withAlpha(128)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 12,
                          color: isSel
                              ? (o == 'all'
                                  ? (isDark ? Brand.darkIconActive : _engAccent)
                                  : c)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        o == 'all'
                            ? 'All'
                            : o.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSel
                              ? (o == 'all'
                                  ? (isDark ? Brand.darkIconActive : _engAccent)
                                  : c)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Returns (color, icon) for a filter chip value
  (Color, IconData?) _chipStyle(String o, bool isDark) {
    switch (o) {
      // Status
      case 'open':
        return (Brand.darkIconActive, Icons.radio_button_unchecked);
      case 'assigned':
        return (const Color(0xFF7986CB), Icons.person_add_rounded);
      case 'in_progress':
        return (const Color(0xFFFFB74D), Icons.autorenew_rounded);
      case 'waiting_customer':
        return (const Color(0xFFCE93D8), Icons.hourglass_top_rounded);
      case 'resolved':
        return (Brand.lightGreenBright, Icons.check_circle_rounded);
      case 'closed':
        return (Brand.darkTextSecondary, Icons.archive_rounded);
      // Priority
      case 'urgent':
        return (const Color(0xFFFF4757), Icons.warning_rounded);
      case 'high':
        return (const Color(0xFFFFB74D), Icons.arrow_upward_rounded);
      case 'medium':
        return (Brand.lightGreenBright, Icons.remove_rounded);
      case 'low':
        return (Brand.darkTextSecondary, Icons.arrow_downward_rounded);
      // Type
      case 'support':
        return (const Color(0xFFFF8A65), Icons.build_rounded);
      case 'inquiry':
        return (Brand.darkIconActive, Icons.help_outline_rounded);
      case 'order':
        return (Brand.lightGreenBright, Icons.shopping_cart_rounded);
      default:
        return (
          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          null,
        );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  RESULT COUNT
  // ═══════════════════════════════════════════════════════════

  Widget _buildResultCount(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [_engAccent, _engAccentDark],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_filteredTickets.length} tickets',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const Spacer(),
          // Sort selector
          GestureDetector(
            onTap: () {
              setState(() {
                _sortBy = _sortBy == 'updated'
                    ? 'priority'
                    : _sortBy == 'priority'
                        ? 'created'
                        : 'updated';
                _applyFilters();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isDark ? Brand.darkIconActive : _engAccent)
                    .withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded,
                      size: 13,
                      color: isDark ? Brand.darkIconActive : _engAccent),
                  const SizedBox(width: 4),
                  Text(
                    _sortBy == 'updated'
                        ? 'Recent'
                        : _sortBy == 'priority'
                            ? 'Priority'
                            : 'Newest',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Brand.darkIconActive : _engAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _resetFilters,
              child: Text(
                'Reset',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? _engAccent : Brand.royalBlueLight,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TICKET CARD
  // ═══════════════════════════════════════════════════════════

  Widget _ticketCard(Map<String, dynamic> ticket, bool isDark) {
    final priority = ticket['priority'] as String? ?? 'medium';
    final status = ticket['status'] as String? ?? 'open';
    final type = ticket['ticket_type'] as String? ?? 'support';
    final customer = ticket['customer'] as Map<String, dynamic>?;
    final machine = ticket['customer_machine'] as Map<String, dynamic>?;
    final catalog = machine?['catalog_machine'] as Map<String, dynamic>?;
    final pColor = _priorityColor(priority);
    final sColor = _statusColor(status);

    IconData typeIcon;
    Color typeColor;
    switch (type) {
      case 'support':
        typeIcon = Icons.build_rounded;
        typeColor = const Color(0xFFFF8A65);
        break;
      case 'inquiry':
        typeIcon = Icons.help_outline_rounded;
        typeColor = Brand.darkIconActive;
        break;
      case 'order':
        typeIcon = Icons.shopping_cart_rounded;
        typeColor = Brand.lightGreenBright;
        break;
      default:
        typeIcon = Icons.confirmation_num_outlined;
        typeColor = Brand.darkTextSecondary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _navigateToDetail(ticket['id']),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(8),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: typeColor.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(12),
                          border: isDark
                              ? Border.all(
                                  color: typeColor.withAlpha(38),
                                )
                              : null,
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${ticket['ticket_number'] ?? ''}',
                              style: TextStyle(
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              ticket['subject'] ?? '',
                              style: TextStyle(
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bdg(
                            priority.toUpperCase(),
                            pColor,
                            isDark,
                          ),
                          const SizedBox(height: 4),
                          _bdg(
                            status.replaceAll('_', ' ').toUpperCase(),
                            sColor,
                            isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                    height: 1,
                  ),
                  const SizedBox(height: 10),
                  // Bottom row
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${customer?['full_name'] ?? 'Unknown'}'
                          '${customer?['company_name'] != null ? " · ${customer!['company_name']}" : ""}',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withAlpha(((isDark ? 0.08 : 0.06) * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _compactTime(ticket['updated_at'] as String?),
                        style: TextStyle(
                          color:
                              isDark ? Brand.darkTextTertiary : Colors.black38,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (catalog != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.settings_suggest_rounded,
                          color:
                              isDark ? Brand.darkTextTertiary : Colors.black26,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${catalog['machine_name'] ?? ''}'
                            '${catalog['model_number'] != null ? ' · ${catalog['model_number']}' : ''}',
                            style: TextStyle(
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Colors.black38,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _bdg(String text, Color c, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withAlpha(((isDark ? 0.2 : 0.15) * 255).toInt())),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c,
            letterSpacing: 0.3,
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════
  //  EMPTY STATE
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState(bool isDark) {
    return RefreshIndicator(
      color: isDark ? Brand.darkIconActive : _engAccent,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      onRefresh: _loadTickets,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.inbox_rounded,
                      size: 40,
                      color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _hasActiveFilters
                        ? 'No tickets match filters'
                        : 'No tickets assigned',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hasActiveFilters
                        ? 'Try adjusting your filters'
                        : 'Tickets assigned to you will appear here',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _resetFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark ? Brand.darkIconActive : _engAccent)
                              .withAlpha(26),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (isDark ? Brand.darkIconActive : _engAccent)
                                .withAlpha(64),
                          ),
                        ),
                        child: Text(
                          'Reset Filters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Brand.darkIconActive : _engAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  SKELETON LOADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildSkeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(77)
                : Brand.royalBlue.withAlpha(13),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(18),
            border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  sk(42, 42, 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sk(60, 10, 5),
                        const SizedBox(height: 6),
                        sk(180, 14, 7),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      sk(55, 18, 6),
                      const SizedBox(height: 4),
                      sk(55, 18, 6),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                height: 1,
              ),
              const SizedBox(height: 10),
              sk(double.infinity, 12, 6),
            ],
          ),
        ),
      ),
    );
  }
}
