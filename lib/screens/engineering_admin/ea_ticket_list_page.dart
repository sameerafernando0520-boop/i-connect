// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_ticket_list_page.dart
// EA Ticket List — Engineering Admin's primary work queue
// Shows ALL service tickets with filter tabs + quick dispatch FAB
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../services/export_service.dart';
import 'ea_ticket_detail_page.dart';
import 'ea_ticket_chat_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

// Filter tabs
enum _TicketFilter { all, unassigned, inProgress, resolved, closed }

// Sort options
enum _SortBy { date, urgency, machineType, zone }

class EaTicketListPage extends StatefulWidget {
  const EaTicketListPage({super.key});

  @override
  State<EaTicketListPage> createState() => _EaTicketListPageState();
}

class _EaTicketListPageState extends State<EaTicketListPage>
    with SingleTickerProviderStateMixin {
  // ── State ──
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _filtered = [];

  _TicketFilter _activeFilter = _TicketFilter.all;
  _SortBy _sortBy = _SortBy.date;
  String _search = '';

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseConfig.client
          .from('service_tickets')
          .select('''
            id, ticket_number, subject, status, priority,
            created_at, updated_at,
            user_id,
            assigned_to,
            customer:users!user_id(id, full_name, profile_photo),
            engineer:users!assigned_to(id, full_name, profile_photo),
            machine:customer_machines(id, catalog:machine_catalog!catalog_machine_id(machine_name, category))
          ''')
          .eq('is_deleted', false)
          .order('created_at', ascending: false);

      // Also get last message time + unread count per ticket
      // (lightweight: just latest message timestamp)
      if (!mounted) return;
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    List<Map<String, dynamic>> list = List.from(_tickets);

    // Tab filter
    switch (_activeFilter) {
      case _TicketFilter.all:
        break;
      case _TicketFilter.unassigned:
        list = list
            .where((t) =>
                t['assigned_to'] == null ||
                (t['status'] == 'new' || t['status'] == 'open'))
            .toList();
        break;
      case _TicketFilter.inProgress:
        list = list
            .where((t) =>
                t['status'] == 'assigned' ||
                t['status'] == 'in_progress' ||
                t['status'] == 'waiting_customer')
            .toList();
        break;
      case _TicketFilter.resolved:
        list = list.where((t) => t['status'] == 'resolved').toList();
        break;
      case _TicketFilter.closed:
        list = list
            .where((t) =>
                t['status'] == 'closed' || t['status'] == 'completed')
            .toList();
        break;
    }

    // Search filter
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((t) {
        final title = (t['subject'] as String? ?? '').toLowerCase();
        final num = (t['ticket_number'] as String? ?? '').toLowerCase();
        final customer = (t['customer'] as Map?)?['full_name'] as String? ?? '';
        final machine = ((t['machine'] as Map?)?['catalog'] as Map?)?['machine_name'] as String? ?? '';
        return title.contains(q) ||
            num.contains(q) ||
            customer.toLowerCase().contains(q) ||
            machine.toLowerCase().contains(q);
      }).toList();
    }

    // Sort
    switch (_sortBy) {
      case _SortBy.date:
        list.sort((a, b) {
          final aDate = DateTime.tryParse(a['created_at'] ?? '') ??
              DateTime(2000);
          final bDate = DateTime.tryParse(b['created_at'] ?? '') ??
              DateTime(2000);
          return bDate.compareTo(aDate);
        });
        break;
      case _SortBy.urgency:
        const order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3};
        list.sort((a, b) => (order[a['priority']] ?? 4)
            .compareTo(order[b['priority']] ?? 4));
        break;
      case _SortBy.machineType:
        list.sort((a, b) {
          final aM =
              ((a['machine'] as Map?)?['catalog'] as Map?)?['category']
                      as String? ??
                  '';
          final bM =
              ((b['machine'] as Map?)?['catalog'] as Map?)?['category']
                      as String? ??
                  '';
          return aM.compareTo(bM);
        });
        break;
      case _SortBy.zone:
        // Zone not on ticket directly, keep date order
        break;
    }

    setState(() => _filtered = list);
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _search = val);
      _applyFilter();
    });
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: AppBar(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Ticket Queue',
          style: TextStyle(
            color: AdminColors.text(context),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: AdminColors.text(context)),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download_outlined,
                color: AdminColors.text(context)),
            tooltip: 'Export to Excel',
            onPressed: _exportToExcel,
          ),
          IconButton(
            icon: Icon(Icons.sort_rounded, color: AdminColors.text(context)),
            tooltip: 'Sort',
            onPressed: () => _showSortSheet(context, isDark),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: _eaAccent),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: TextStyle(color: AdminColors.text(context)),
                  decoration: InputDecoration(
                    hintText: 'Search tickets, customers, machines...',
                    hintStyle:
                        TextStyle(color: AdminColors.textHint(context)),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AdminColors.textHint(context)),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: AdminColors.textHint(context)),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                              _applyFilter();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Brand.darkCardElevated
                        : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              // Filter tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: _TicketFilter.values.map((f) {
                    final selected = _activeFilter == f;
                    final count = _countForFilter(f);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _activeFilter = f);
                          _applyFilter();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? _eaAccent
                                : (isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? _eaAccent
                                  : AdminColors.border(context),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _filterLabel(f),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AdminColors.textSub(context),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              if (count > 0) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? Colors.white.withAlpha(60)
                                        : _eaAccent.withAlpha(30),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : _eaAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(context, isDark),
      floatingActionButton: _activeFilter == _TicketFilter.unassigned ||
              _activeFilter == _TicketFilter.all
          ? FloatingActionButton.extended(
              onPressed: () => _showQuickDispatch(context, isDark),
              backgroundColor: _eaAccent,
              icon: const Icon(Icons.bolt_rounded, color: Colors.white),
              label: const Text(
                'Dispatch',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (_loading) return _buildShimmer(isDark);
    if (_error != null) return _buildError(context, isDark);
    if (_filtered.isEmpty) return _buildEmpty(context, isDark);

    return RefreshIndicator(
      onRefresh: _load,
      color: _eaAccent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _filtered.length,
        itemBuilder: (context, i) =>
            _TicketCard(
              ticket: _filtered[i],
              isDark: isDark,
              onTap: () => _openDetail(context, _filtered[i]),
              onChatTap: () => _openChat(context, _filtered[i]),
            ),
      ),
    );
  }

  void _openDetail(BuildContext context, Map<String, dynamic> ticket) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EaTicketDetailPage(ticketId: ticket['id'] as String),
      ),
    ).then((_) => _load());
  }

  void _openChat(BuildContext context, Map<String, dynamic> ticket) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EaTicketChatPage(
          ticketId: ticket['id'] as String,
          ticketTitle: ticket['subject'] as String? ?? 'Ticket',
        ),
      ),
    ).then((_) => _load());
  }

  // ── Export to Excel (v24) ────────────────────────────────────
  Future<void> _exportToExcel() async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export with current filters.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing Excel export…')),
    );
    final path =
        await ExportService.instance.exportServiceTickets(_filtered);
    if (!mounted) return;
    ExportService.showResult(context, path);
  }

  // ── Sort sheet ────────────────────────────────────────────────

  void _showSortSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AdminColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Sort By',
                style: TextStyle(
                  color: AdminColors.text(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ..._SortBy.values.map((s) {
              final selected = _sortBy == s;
              return ListTile(
                leading: Icon(
                  _sortIcon(s),
                  color: selected ? _eaAccent : AdminColors.textSub(context),
                ),
                title: Text(
                  _sortLabel(s),
                  style: TextStyle(
                    color: selected
                        ? _eaAccent
                        : AdminColors.text(context),
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: _eaAccent)
                    : null,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _sortBy = s);
                  _applyFilter();
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Quick dispatch sheet ──────────────────────────────────────

  void _showQuickDispatch(BuildContext context, bool isDark) {
    final unassigned = _tickets
        .where((t) =>
            t['assigned_to'] == null &&
            (t['status'] == 'new' || t['status'] == 'open'))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AdminColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: _eaAccent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Dispatch',
                    style: TextStyle(
                      color: AdminColors.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${unassigned.length} unassigned',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: unassigned.isEmpty
                  ? Center(
                      child: Text(
                        'No unassigned tickets 🎉',
                        style: TextStyle(color: AdminColors.textSub(context)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: unassigned.length,
                      itemBuilder: (_, i) {
                        final t = unassigned[i];
                        final customer =
                            (t['customer'] as Map?)?['full_name'] as String? ??
                                'Customer';
                        final machine =
                            ((t['machine'] as Map?)?['catalog'] as Map?)?['machine_name'] as String? ??
                                'Machine';
                        return Card(
                          color: isDark
                              ? Brand.darkCardElevated
                              : Brand.scaffoldLight,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.warning_amber_rounded,
                                  color: Color(0xFFEF4444), size: 20),
                            ),
                            title: Text(
                              t['subject'] as String? ?? 'Ticket',
                              style: TextStyle(
                                color: AdminColors.text(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$customer · $machine',
                              style: TextStyle(
                                color: AdminColors.textSub(context),
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded,
                                size: 14),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _openChat(context, t);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  int _countForFilter(_TicketFilter f) {
    switch (f) {
      case _TicketFilter.all:
        return _tickets.length;
      case _TicketFilter.unassigned:
        return _tickets
            .where((t) =>
                t['assigned_to'] == null &&
                (t['status'] == 'new' || t['status'] == 'open'))
            .length;
      case _TicketFilter.inProgress:
        return _tickets
            .where((t) =>
                t['status'] == 'assigned' ||
                t['status'] == 'in_progress' ||
                t['status'] == 'waiting_customer')
            .length;
      case _TicketFilter.resolved:
        return _tickets.where((t) => t['status'] == 'resolved').length;
      case _TicketFilter.closed:
        return _tickets
            .where((t) =>
                t['status'] == 'closed' || t['status'] == 'completed')
            .length;
    }
  }

  String _filterLabel(_TicketFilter f) {
    switch (f) {
      case _TicketFilter.all:
        return 'All';
      case _TicketFilter.unassigned:
        return 'Unassigned';
      case _TicketFilter.inProgress:
        return 'In Progress';
      case _TicketFilter.resolved:
        return 'Resolved';
      case _TicketFilter.closed:
        return 'Closed';
    }
  }

  String _sortLabel(_SortBy s) {
    switch (s) {
      case _SortBy.date:
        return 'Date (Newest first)';
      case _SortBy.urgency:
        return 'Urgency (Critical first)';
      case _SortBy.machineType:
        return 'Machine Type';
      case _SortBy.zone:
        return 'Zone';
    }
  }

  IconData _sortIcon(_SortBy s) {
    switch (s) {
      case _SortBy.date:
        return Icons.calendar_today_rounded;
      case _SortBy.urgency:
        return Icons.priority_high_rounded;
      case _SortBy.machineType:
        return Icons.precision_manufacturing_rounded;
      case _SortBy.zone:
        return Icons.map_rounded;
    }
  }

  // ── Loading / Error / Empty ───────────────────────────────────

  Widget _buildShimmer(bool isDark) {
    final shimmer = isDark ? Brand.darkCardElevated : const Color(0xFFE2E8F0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: shimmer,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load tickets',
              style: TextStyle(
                color: AdminColors.text(context),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(
                  color: AdminColors.textSub(context), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_rounded,
              size: 56, color: AdminColors.textHint(context)),
          const SizedBox(height: 12),
          Text(
            _search.isNotEmpty
                ? 'No tickets match "$_search"'
                : 'No tickets in this category',
            style: TextStyle(
              color: AdminColors.textSub(context),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Ticket Card Widget
// ═══════════════════════════════════════════════════════════════

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onChatTap;

  const _TicketCard({
    required this.ticket,
    required this.isDark,
    required this.onTap,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = ticket['subject'] as String? ?? 'Ticket';
    final ticketNum = ticket['ticket_number'] as String? ?? '';
    final status = ticket['status'] as String? ?? 'open';
    final priority = ticket['priority'] as String? ?? 'medium';
    final customer =
        (ticket['customer'] as Map?)?['full_name'] as String? ?? 'Customer';
    final engineer = ticket['engineer'] as Map?;
    final engineerName = engineer?['full_name'] as String?;
    final engineerPhoto = engineer?['profile_photo'] as String?;
    final machine = ticket['machine'] as Map?;
    final machineName = (machine?['catalog'] as Map?)?['machine_name'] as String? ?? 'Machine';
    final machineCategory =
        (machine?['catalog'] as Map?)?['category'] as String? ?? '';
    final isUnassigned = ticket['assigned_to'] == null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnassigned
                ? const Color(0xFFEF4444).withAlpha(80)
                : AdminColors.border(context),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 30 : 8),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Machine icon
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _categoryColor(machineCategory).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _categoryIcon(machineCategory),
                      color: _categoryColor(machineCategory),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: AdminColors.text(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$customer · $machineName',
                          style: TextStyle(
                            color: AdminColors.textSub(context),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PriorityDot(priority: priority),
                ],
              ),
            ),

            // Bottom row: ticket number, status, engineer, time, chat button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  // Ticket number
                  Text(
                    ticketNum,
                    style: TextStyle(
                      color: AdminColors.textHint(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  _StatusBadge(status: status),
                  const Spacer(),
                  // Engineer avatar or unassigned chip
                  isUnassigned
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFEF4444).withAlpha(40)),
                          ),
                          child: const Text(
                            'Unassigned',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MiniAvatar(
                                photoUrl: engineerPhoto,
                                name: engineerName ?? '?'),
                            const SizedBox(width: 5),
                            Text(
                              engineerName?.split(' ').first ?? 'Engineer',
                              style: TextStyle(
                                color: AdminColors.textSub(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(width: 8),
                  // Chat button
                  GestureDetector(
                    onTap: onChatTap,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _eaAccent.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.chat_bubble_rounded,
                          size: 16, color: _eaAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    final c = category.toLowerCase();
    if (c.contains('witcolor') || c.contains('uv')) return const Color(0xFF8B5CF6);
    if (c.contains('laser')) return const Color(0xFFEF4444);
    if (c.contains('cnc')) return const Color(0xFF10B981);
    if (c.contains('fiber')) return const Color(0xFFF97316);
    return Brand.royalBlue;
  }

  IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('laser') || c.contains('fiber')) {
      return Icons.electric_bolt_rounded;
    }
    if (c.contains('cnc')) return Icons.settings_rounded;
    return Icons.print_rounded;
  }
}

// ── Mini avatar ──────────────────────────────────────────────────────────────

class _MiniAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _MiniAvatar({required this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _eaAccent.withAlpha(80)),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: 24,
                height: 24,
                errorWidget: (_, __, ___) => _initials(initials),
              )
            : _initials(initials),
      ),
    );
  }

  Widget _initials(String i) => Container(
        color: _eaAccent.withAlpha(20),
        child: Center(
          child: Text(i,
              style: const TextStyle(
                  color: _eaAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      );
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = AdminColors.statusColor(status);
    final label = _label(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _label(String s) {
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
        return 'Waiting';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      case 'completed':
        return 'Completed';
      default:
        return s;
    }
  }
}

// ── Priority dot ─────────────────────────────────────────────────────────────

class _PriorityDot extends StatelessWidget {
  final String priority;

  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AdminColors.priorityColor(priority),
      ),
    );
  }
}
