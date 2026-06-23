// ============================================================
// FILE: lib/screens/customer/support_tickets_page.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/ic_icons.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';
import 'create_support_ticket_page.dart';
import 'ticket_detail_page.dart';
import '../../widgets/ds/ds_widgets.dart';

class SupportTicketsPage extends StatefulWidget {
  final bool showNavBar;
  const SupportTicketsPage({super.key, this.showNavBar = true});

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _tickets = [];
  bool _isLoading = true;
  String _filterStatus = 'all';
  late TabController _tabController;

  final Map<String, Map<String, dynamic>> _statusConfig = {
    'all': {
      'label': 'All',
      'icon': Icons.list_alt_rounded,
      'color': Brand.royalBlueDark,
    },
    // L2: Pull semantic colors from StatusColors so the palette is shared
    // across every screen that renders ticket state. Previously these were
    // inlined hex codes — one more place to drift out of sync.
    'open': {
      'label': 'Open',
      'icon': Icons.radio_button_checked_rounded,
      'color': StatusColors.open,
    },
    'assigned': {
      'label': 'Assigned',
      'icon': Icons.person_add_rounded,
      'color': StatusColors.assigned,
    },
    'in_progress': {
      'label': 'Working',
      'icon': Icons.engineering_rounded,
      'color': StatusColors.inProgress,
    },
    'waiting_customer': {
      'label': 'Waiting',
      'icon': Icons.hourglass_top_rounded,
      'color': StatusColors.waiting,
    },
    'resolved': {
      'label': 'Resolved',
      'icon': Icons.check_circle_rounded,
      'color': Brand.lightGreen,
    },
    'closed': {
      'label': 'Closed',
      'icon': Icons.archive_rounded,
      'color': StatusColors.closed,
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final data =
          await SupabaseConfig.client.from('service_tickets').select('''
            *,
            customer_machines!service_tickets_customer_machine_id_fkey(
              serial_number,
              machine_catalog!customer_machines_catalog_machine_id_fkey(
                machine_name,
                brand,
                image_url,
                category
              )
            ),
            catalog_direct:machine_catalog!service_tickets_catalog_machine_id_fkey(
              machine_name,
              brand,
              image_url,
              category
            )
          ''')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
      // v24 fix: keep the shell badge in sync when the user enters via the
      // tickets tab directly (without going through the home tab).
      const active = {
        'new', 'open', 'assigned', 'in_progress', 'waiting_customer',
      };
      final openCount =
          _tickets.where((t) => active.contains(t['status'])).length;
      CustomerNavController.setOpenTickets(openCount);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Error: $e')),
            ],
          ),
          backgroundColor: StatusColors.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        ),
      );
    }
  }

  int _getStatusCount(String status, String type) {
    List<Map<String, dynamic>> typed;
    if (type == 'inquiry') {
      typed = _tickets
          .where((t) =>
              t['ticket_type'] == 'inquiry' || t['ticket_type'] == 'order')
          .toList();
    } else {
      typed = _tickets.where((t) => t['ticket_type'] == type).toList();
    }
    if (status == 'all') return typed.length;
    return typed.where((t) => t['status'] == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildTopBar(isDark),
            _buildSummaryCards(isDark),
            _buildTabBar(isDark),
            _buildStatusFilter(isDark),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState(isDark)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTicketList('support', isDark),
                        _buildTicketList('inquiry', isDark),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(isDark),
      bottomNavigationBar: widget.showNavBar
          ? CustomerNavBar(
              currentIndex: 2,
              onTabSelected: CustomerNavController.switchTab,
            )
          : null,
    );
  }

  // ─── TOP BAR — Navy Glow hero ──────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return DsPageHeader(
      title: 'Support & Inquiries',
      subtitle: '${_tickets.length} total tickets',
      showBack: !widget.showNavBar,
      actions: [
        GestureDetector(
          onTap: _loadTickets,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(Brand.r(12)),
              border: Border.all(color: const Color(0xFF2A3F6E)),
            ),
            child: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 19),
          ),
        ),
      ],
    );
  }

  // ─── SUMMARY CARDS ─────────────────────────────────────────
  Widget _buildSummaryCards(bool isDark) {
    // v24 fix: include waiting_customer per project spec — it's still active
    const activeStatuses = {
      'new', 'open', 'assigned', 'in_progress', 'waiting_customer',
    };
    final open =
        _tickets.where((t) => activeStatuses.contains(t['status'])).length;
    final inProgress =
        _tickets.where((t) => t['status'] == 'in_progress').length;
    final resolved = _tickets
        .where((t) =>
            t['status'] == 'resolved' ||
            t['status'] == 'closed' ||
            t['status'] == 'completed')
        .length;

    // Stat tiles overlap the hero's curved bottom edge (Navy Glow signature).
    return DsStatRow(
      tiles: [
        DsStatTile(
          icon: Icons.radio_button_checked_rounded,
          color: StatusColors.open,
          value: '$open',
          label: S.of(context)!.ticketStatusOpen,
        ),
        DsStatTile(
          icon: Icons.engineering_rounded,
          color: StatusColors.inProgress,
          value: '$inProgress',
          label: S.of(context)!.ticketStatusInProgress,
        ),
        DsStatTile(
          icon: Icons.check_circle_rounded,
          color: StatusColors.success,
          value: '$resolved',
          label: S.of(context)!.ticketStatusResolved,
        ),
      ],
    );
  }

  // ─── TAB BAR ───────────────────────────────────────────────
  Widget _buildTabBar(bool isDark) {

    // Only count open/active tickets (not resolved/closed)
    const activeStatuses = {
      'new',
      'open',
      'assigned',
      'in_progress',
      'waiting_customer'
    };
    final supportCount = _tickets
        .where((t) =>
            t['ticket_type'] == 'support' &&
            activeStatuses.contains(t['status']))
        .length;
    final inquiryCount = _tickets
        .where((t) =>
            (t['ticket_type'] == 'inquiry' || t['ticket_type'] == 'order') &&
            activeStatuses.contains(t['status']))
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Brand.darkIconActive,
                    Brand.darkIconActive.withAlpha(204),
                  ]
                : [Brand.royalBlueDark, Brand.royalBlue],
          ),
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        labelColor: isDark ? const Color(0xFF1A1F36) : Colors.white,
        unselectedLabelColor:
            isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.build_rounded, size: 16),
                const SizedBox(width: 6),
                Text(S.of(context)!.supportTitle),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: Text(
                    '$supportCount',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_bag_rounded, size: 16),
                const SizedBox(width: 6),
                Text(S.of(context)!.inquiryTitle),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: Text(
                    '$inquiryCount',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATUS FILTER ─────────────────────────────────────────
  Widget _buildStatusFilter(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;
    final currentTabType = _tabController.index == 0 ? 'support' : 'inquiry';
    final statuses = [
      'all',
      'open',
      'in_progress',
      'resolved',
      'closed',
    ];

    return Container(
      height: 52,
      margin: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: statuses.length,
        itemBuilder: (context, index) {
          final status = statuses[index];
          final config = _statusConfig[status]!;
          final isSelected = _filterStatus == status;
          final count = _getStatusCount(status, currentTabType);
          final color =
              status == 'all' && isDark ? accent : config['color'] as Color;

          return GestureDetector(
            onTap: () => setState(() => _filterStatus = status),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color
                    : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                  color: isSelected
                      ? color
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    config['icon'] as IconData,
                    size: 14,
                    color: isSelected
                        ? (isDark ? const Color(0xFF1A1F36) : Colors.white)
                        : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(context, status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? const Color(0xFF1A1F36) : Colors.white)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withAlpha(
                                ((isDark ? 0.3 : 0.25) * 255).toInt())
                            : color.withAlpha(
                                ((isDark ? 0.15 : 0.1) * 255).toInt()),
                        borderRadius: BorderRadius.circular(Brand.r(8)),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? (isDark
                                  ? const Color(0xFF1A1F36)
                                  : Colors.white)
                              : color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── TICKET LIST ───────────────────────────────────────────
  Widget _buildTicketList(String type, bool isDark) {
    List<Map<String, dynamic>> filtered;
    if (type == 'inquiry') {
      filtered = _tickets
          .where((t) =>
              t['ticket_type'] == 'inquiry' || t['ticket_type'] == 'order')
          .toList();
    } else {
      filtered = _tickets.where((t) => t['ticket_type'] == type).toList();
    }

    if (_filterStatus != 'all') {
      filtered = filtered.where((t) => t['status'] == _filterStatus).toList();
    }

    if (filtered.isEmpty) {
      return _buildEmptyState(type, isDark);
    }

    return RefreshIndicator(
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: Brand.surface(isDark),
      onRefresh: _loadTickets,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          return _buildTicketCard(filtered[index], isDark);
        },
      ),
    );
  }

  // ─── TICKET CARD ───────────────────────────────────────────
  Widget _buildTicketCard(Map<String, dynamic> ticket, bool isDark) {
    final customerMachine =
        ticket['customer_machines'] as Map<String, dynamic>?;
    final catalog =
        customerMachine?['machine_catalog'] as Map<String, dynamic>?;
    final directCatalog = ticket['catalog_direct'] as Map<String, dynamic>?;
    final machineInfo = catalog ?? directCatalog;

    final status = ticket['status'] ?? 'open';
    final priority = ticket['priority'] ?? 'medium';
    final ticketType = ticket['ticket_type'] ?? 'support';
    final createdAt = DateTime.parse(ticket['created_at']);
    final statusConfig = _statusConfig[status];
    final statusColor = (statusConfig?['color'] as Color?) ?? Colors.grey;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: ticket['id']),
          ),
        ).then((_) {
          if (mounted) _loadTickets();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          children: [
            // ── Top Color Bar ──
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: _getPriorityColor(priority),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(Brand.r(18))),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header Row ──
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _getTypeColor(ticketType)
                              .withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(11)),
                        ),
                        child: Icon(
                          _getTypeIcon(ticketType),
                          color: _getTypeColor(ticketType),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket['ticket_number'] ?? 'N/A',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              TimeUtils.getTimeAgo(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: (isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight)
                                    .withAlpha(179),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(
                              ((isDark ? 0.15 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(
                            color: statusColor.withAlpha(
                                ((isDark ? 0.35 : 0.3) * 255).toInt()),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _formatStatus(context, status).toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Subject ──
                  Text(
                    ticket['subject'] ?? 'No Subject',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (ticket['description'] != null &&
                      ticket['description'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      ticket['description'],
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // ── Machine Info ──
                  if (machineInfo != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        border: Border.all(
                            color:
                                isDark ? Brand.darkBorder : Brand.borderLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Brand.surface(isDark),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
                              border: Border.all(
                                  color: isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight),
                            ),
                            child: machineInfo['image_url'] != null &&
                                    machineInfo['image_url'] != ''
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(Brand.r(10)),
                                    child: CachedNetworkImage(
                                      imageUrl: machineInfo['image_url'],
                                      fit: BoxFit.cover,
                                      width: 42,
                                      height: 42,
                                      placeholder: (_, __) => Icon(
                                        _getCategoryIcon(
                                            machineInfo['category']),
                                        size: 20,
                                        color: isDark
                                            ? Brand.darkIconActive
                                            : Brand.royalBlueDark,
                                      ),
                                      errorWidget: (_, __, ___) => Icon(
                                        _getCategoryIcon(
                                            machineInfo['category']),
                                        size: 20,
                                        color: isDark
                                            ? Brand.darkIconActive
                                            : Brand.royalBlueDark,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    _getCategoryIcon(machineInfo['category']),
                                    size: 20,
                                    color: isDark
                                        ? Brand.darkIconActive
                                        : Brand.royalBlueDark,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  machineInfo['machine_name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (customerMachine?['serial_number'] != null)
                                  Text(
                                    'S/N: ${customerMachine!['serial_number']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Brand.surface(isDark),
                              borderRadius: BorderRadius.circular(Brand.r(8)),
                              border: Border.all(
                                  color: isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight),
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: isDark
                                  ? Brand.darkIconActive
                                  : Brand.royalBlueDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Bottom Row: Priority ──
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getPriorityColor(priority).withAlpha(
                              ((isDark ? 0.15 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(8)),
                          border: Border.all(
                            color: _getPriorityColor(priority).withAlpha(
                                ((isDark ? 0.35 : 0.3) * 255).toInt()),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _getPriorityColor(priority),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              priority.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _getPriorityColor(priority),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getTypeColor(ticketType).withAlpha(
                              ((isDark ? 0.15 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(8)),
                          border: Border.all(
                            color: _getTypeColor(ticketType).withAlpha(
                                ((isDark ? 0.35 : 0.3) * 255).toInt()),
                          ),
                        ),
                        child: Text(
                          ticketType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _getTypeColor(ticketType),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color: (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)
                                .withAlpha(179),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: (isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight)
                                  .withAlpha(179),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _buildEmptyState(String type, bool isDark) {
    final isSupport = type == 'support';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(24)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withAlpha(((isDark ? 0.2 : 0.04) * 255).toInt()),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkIconActive.withAlpha(26)
                      : Brand.royalBlueDark.withAlpha(15),
                  borderRadius: BorderRadius.circular(Brand.r(24)),
                ),
                child: isSupport
                    ? IcChatGearIcon(
                        size: 38,
                        color:
                            isDark ? Brand.darkIconActive : Brand.royalBlueDark,
                      )
                    : Icon(
                        Icons.shopping_bag_rounded,
                        size: 38,
                        color:
                            isDark ? Brand.darkIconActive : Brand.royalBlueDark,
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                isSupport
                    ? S.of(context)!.ticketNoSupport
                    : S.of(context)!.ticketNoInquiries,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isSupport
                    ? S.of(context)!.ticketNoSupportDesc
                    : S.of(context)!.ticketNoInquiriesDesc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (isSupport)
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateSupportTicketPage(),
                        ),
                      ).then((_) {
                        if (mounted) _loadTickets();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  Brand.lightGreenBright,
                                  Brand.lightGreenBright.withAlpha(204),
                                ]
                              : [
                                  Brand.lightGreen,
                                  Brand.lightGreenDark,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark
                                    ? Brand.lightGreenBright
                                    : Brand.lightGreen)
                                .withAlpha(77),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 18,
                              color: isDark
                                  ? const Color(0xFF1A1F36)
                                  : Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            S.of(context)!.ticketCreate,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFF1A1F36)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── LOADING STATE ─────────────────────────────────────────
  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(20)),
            ),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading tickets...',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FAB ───────────────────────────────────────────────────
  Widget _buildFAB(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  Brand.lightGreenBright,
                  Brand.lightGreenBright.withAlpha(204),
                ]
              : [Brand.lightGreen, Brand.lightGreenDark],
        ),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                .withAlpha(102),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSupportTicketPage()),
          ).then((_) {
            if (mounted) _loadTickets();
          });
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: Icon(Icons.add_rounded,
            color: isDark ? const Color(0xFF1A1F36) : Colors.white, size: 22),
        label: Text(
          S.of(context)!.ticketNewTicket,
          style: TextStyle(
            color: isDark ? const Color(0xFF1A1F36) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────────────────────
  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFE53935);
      case 'high':
        return const Color(0xFFFF9800);
      case 'medium':
        return const Color(0xFF2196F3);
      case 'low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'support':
        return Brand.royalBlueDark;
      case 'inquiry':
        return Brand.lightGreen;
      case 'order':
        return const Color(0xFFFF9800);
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'support':
        return Icons.build_rounded;
      case 'inquiry':
        return Icons.chat_bubble_rounded;
      case 'order':
        return Icons.shopping_cart_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Digital Printers':
        return Icons.print_rounded;
      case 'CNC Routers':
        return Icons.precision_manufacturing_rounded;
      case 'Laser Cutters':
        return Icons.content_cut_rounded;
      case 'Finishing Equipment':
        return Icons.construction_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  String _statusLabel(BuildContext context, String status) {
    final t = S.of(context)!;
    switch (status) {
      case 'all':
        return t.commonAll;
      case 'open':
        return t.ticketStatusOpen;
      case 'assigned':
        return t.ticketFilterAssigned;
      case 'in_progress':
        return t.ticketFilterWorking;
      case 'waiting_customer':
        return t.ticketFilterWaiting;
      case 'resolved':
        return t.ticketStatusResolved;
      case 'closed':
        return t.ticketStatusClosed;
      default:
        return (_statusConfig[status]?['label'] as String?) ??
            status.replaceAll('_', ' ').toUpperCase();
    }
  }

  String _formatStatus(BuildContext context, String status) =>
      _statusLabel(context, status);

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
