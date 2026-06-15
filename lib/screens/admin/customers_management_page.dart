// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/admin/customers_management_page.dart
// REWRITTEN v18 — Full dark mode pass, CachedNetworkImage,
//   AdminColors context-aware methods, .withAlpha() throughout
//   Fixed v19: map mutation, mounted checks, sort try/catch,
//   AlwaysScrollableScrollPhysics, sheetCtx, spread copy
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../services/export_service.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/ic_icons.dart';
import 'customer_detail_page.dart';

class CustomersManagementPage extends StatefulWidget {
  const CustomersManagementPage({super.key});

  @override
  State<CustomersManagementPage> createState() =>
      _CustomersManagementPageState();
}

class _CustomersManagementPageState extends State<CustomersManagementPage> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _sortBy = 'newest';
  String _filterType = 'all';

  // ── Grouping ────────────────────────────────────────────────
  // 'none' = flat list (default behaviour).
  // 'province' / 'district' / 'connector' = customers are grouped by that
  // attribute when the admin selects one of those options.
  // _groupValue holds the optional sub-filter (e.g. only show customers
  // in a specific province, district, or connector).
  String _groupBy = 'none';
  String? _groupValue;

  // Cache of connectors keyed by id → connector profile, so we can show
  // names for users.connector_id without doing N round-trips per render.
  // Populated lazily the first time the admin opens the grouping sheet.
  Map<String, Map<String, dynamic>> _connectorsById = {};
  List<Map<String, dynamic>> _allConnectorsList = [];
  bool _loadingConnectorsList = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> customers;

      try {
        final result =
            await SupabaseConfig.client.rpc('get_customers_with_stats');
        if (!mounted) return;
        customers = List<Map<String, dynamic>>.from(result as List);
      } catch (_) {
        customers = await _loadCustomersFallback();
        if (!mounted) return;
      }

      setState(() {
        _customers = customers;
        _applyFilters();
        _isLoading = false;
      });
      // Best-effort connector hydration so the chip on each card shows the
      // assigned connector's name instead of a bare id. Non-blocking.
      _ensureConnectorsLoaded();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Error loading customers: $e', isError: true);
    }
  }

  Future<List<Map<String, dynamic>>> _loadCustomersFallback() async {
    final data = await SupabaseConfig.client
        .from('users')
        .select('*')
        .eq('role', 'customer')
        .order('created_at', ascending: false);

    // ── Immutable base list — NO direct mutation ──
    final rawCustomers = List<Map<String, dynamic>>.from(data);

    if (rawCustomers.isEmpty) return rawCustomers;

    final customerIds = rawCustomers.map((c) => c['id'] as String).toList();

    final results = await Future.wait<dynamic>([
      SupabaseConfig.client
          .from('customer_machines')
          .select('user_id')
          .inFilter('user_id', customerIds),
      SupabaseConfig.client
          .from('service_tickets')
          .select('user_id, ticket_type, status')
          .inFilter('user_id', customerIds)
          .eq('is_deleted', false),
    ]);

    final allMachines = results[0] as List;
    final allTickets = results[1] as List;

    final machineCounts = <String, int>{};
    final ticketCounts = <String, int>{};
    final inquiryCounts = <String, int>{};
    final openTicketCounts = <String, int>{};

    for (final m in allMachines) {
      final uid = m['user_id'] as String;
      machineCounts[uid] = (machineCounts[uid] ?? 0) + 1;
    }

    for (final t in allTickets) {
      final uid = t['user_id'] as String;
      final type = t['ticket_type'] as String?;
      final status = t['status'] as String?;

      if (type == 'inquiry') {
        inquiryCounts[uid] = (inquiryCounts[uid] ?? 0) + 1;
      } else {
        ticketCounts[uid] = (ticketCounts[uid] ?? 0) + 1;
      }

      if (status == 'open' || status == 'assigned' || status == 'in_progress') {
        openTicketCounts[uid] = (openTicketCounts[uid] ?? 0) + 1;
      }
    }

    // ── Build new maps via spread — NO mutation ──
    return rawCustomers.map((customer) {
      final id = customer['id'] as String;
      return {
        ...customer,
        'machine_count': machineCounts[id] ?? 0,
        'ticket_count': ticketCounts[id] ?? 0,
        'inquiry_count': inquiryCounts[id] ?? 0,
        'open_ticket_count': openTicketCounts[id] ?? 0,
      };
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // FILTERING & SORTING
  // ═══════════════════════════════════════════════════════════

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_customers);

    // ── Search ──
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final company = (c['company_name'] ?? '').toString().toLowerCase();
        final email = (c['email'] ?? '').toString().toLowerCase();
        final phone = (c['phone_number'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            company.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // ── Filter ──
    switch (_filterType) {
      case 'with_machines':
        filtered =
            filtered.where((c) => (c['machine_count'] ?? 0) > 0).toList();
        break;
      case 'with_tickets':
        filtered = filtered.where((c) => (c['ticket_count'] ?? 0) > 0).toList();
        break;
      case 'active':
        filtered =
            filtered.where((c) => (c['open_ticket_count'] ?? 0) > 0).toList();
        break;
      case 'new':
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        filtered = filtered.where((c) {
          try {
            return DateTime.parse(c['created_at']).isAfter(weekAgo);
          } catch (_) {
            return false;
          }
        }).toList();
        break;
      case 'with_inquiries':
        filtered =
            filtered.where((c) => (c['inquiry_count'] ?? 0) > 0).toList();
        break;
    }

    // ── Group sub-filter (only when an explicit value picked) ──
    if (_groupBy != 'none' && _groupValue != null) {
      switch (_groupBy) {
        case 'province':
          filtered = filtered
              .where((c) =>
                  ((c['province'] as String?) ?? '') == _groupValue)
              .toList();
          break;
        case 'district':
          filtered = filtered
              .where((c) =>
                  ((c['district'] as String?) ?? '') == _groupValue)
              .toList();
          break;
        case 'connector':
          // _groupValue == '__none__' means "no connector assigned"
          if (_groupValue == '__none__') {
            filtered = filtered
                .where((c) => (c['connector_id'] as String?) == null)
                .toList();
          } else {
            filtered = filtered
                .where(
                    (c) => (c['connector_id'] as String?) == _groupValue)
                .toList();
          }
          break;
      }
    }

    // ── Sort ──
    switch (_sortBy) {
      case 'newest':
        filtered.sort((a, b) {
          try {
            return DateTime.parse(b['created_at'])
                .compareTo(DateTime.parse(a['created_at']));
          } catch (_) {
            return 0;
          }
        });
        break;
      case 'oldest':
        filtered.sort((a, b) {
          try {
            return DateTime.parse(a['created_at'])
                .compareTo(DateTime.parse(b['created_at']));
          } catch (_) {
            return 0;
          }
        });
        break;
      case 'most_machines':
        filtered.sort((a, b) => ((b['machine_count'] ?? 0) as int)
            .compareTo((a['machine_count'] ?? 0) as int));
        break;
      case 'most_tickets':
        filtered.sort((a, b) => ((b['ticket_count'] ?? 0) as int)
            .compareTo((a['ticket_count'] ?? 0) as int));
        break;
      case 'most_inquiries':
        filtered.sort((a, b) => ((b['inquiry_count'] ?? 0) as int)
            .compareTo((a['inquiry_count'] ?? 0) as int));
        break;
      case 'name_az':
        filtered.sort((a, b) => (a['full_name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['full_name'] ?? '').toString().toLowerCase()));
        break;
      case 'by_province':
        filtered.sort((a, b) {
          final ap = (a['province'] as String? ?? '\u{FFFF}');
          final bp = (b['province'] as String? ?? '\u{FFFF}');
          final c = ap.compareTo(bp);
          if (c != 0) return c;
          return (a['full_name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['full_name'] ?? '').toString().toLowerCase());
        });
        break;
      case 'by_district':
        filtered.sort((a, b) {
          final ad = (a['district'] as String? ?? '\u{FFFF}');
          final bd = (b['district'] as String? ?? '\u{FFFF}');
          final c = ad.compareTo(bd);
          if (c != 0) return c;
          return (a['full_name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['full_name'] ?? '').toString().toLowerCase());
        });
        break;
      case 'by_connector':
        filtered.sort((a, b) {
          final ac = _connectorsById[a['connector_id']]?['full_name']
                  ?.toString()
                  .toLowerCase() ??
              '\u{FFFF}';
          final bc = _connectorsById[b['connector_id']]?['full_name']
                  ?.toString()
                  .toLowerCase() ??
              '\u{FFFF}';
          final c = ac.compareTo(bc);
          if (c != 0) return c;
          return (a['full_name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['full_name'] ?? '').toString().toLowerCase());
        });
        break;
    }

    _filteredCustomers = filtered;
  }

  // ── Connector list loader for the grouping picker ───────────
  Future<void> _ensureConnectorsLoaded() async {
    if (_allConnectorsList.isNotEmpty || _loadingConnectorsList) return;
    setState(() => _loadingConnectorsList = true);
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, role, profile_photo')
          .inFilter('role', const ['marketing_admin', 'admin', 'super_admin'])
          .or('is_active.is.null,is_active.eq.true')
          .order('full_name');
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _allConnectorsList = list;
        _connectorsById = {for (final c in list) c['id'] as String: c};
        _loadingConnectorsList = false;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Failed to load connectors: $e');
      if (!mounted) return;
      setState(() => _loadingConnectorsList = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // COMPUTED COUNTS
  // ═══════════════════════════════════════════════════════════

  int get _withMachinesCount =>
      _customers.where((c) => (c['machine_count'] ?? 0) > 0).length;

  int get _withTicketsCount =>
      _customers.where((c) => (c['ticket_count'] ?? 0) > 0).length;

  int get _activeCount =>
      _customers.where((c) => (c['open_ticket_count'] ?? 0) > 0).length;

  int get _withInquiriesCount =>
      _customers.where((c) => (c['inquiry_count'] ?? 0) > 0).length;

  int get _newThisWeekCount {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _customers.where((c) {
      try {
        return DateTime.parse(c['created_at']).isAfter(weekAgo);
      } catch (_) {
        return false;
      }
    }).length;
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _getSortLabel() {
    switch (_sortBy) {
      case 'newest':
        return 'Newest';
      case 'oldest':
        return 'Oldest';
      case 'most_machines':
        return 'Machines ↓';
      case 'most_tickets':
        return 'Tickets ↓';
      case 'most_inquiries':
        return 'Inquiries ↓';
      case 'name_az':
        return 'A → Z';
      default:
        return 'Newest';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : AdminColors.bg(context),
      appBar: DsPageHeader(
        title: 'Customers',
        subtitle: '${_customers.length} registered',
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.file_download_outlined, color: Colors.white), onPressed: _exportToExcel),
          IconButton(icon: const Icon(Icons.sort_rounded, color: Colors.white), onPressed: () => _showSortOptions(isDark)),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _loadCustomers),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(isDark),
            _buildFilterChips(isDark),
            _buildResultsCount(isDark),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState(isDark)
                  : _filteredCustomers.isEmpty
                      ? _buildEmptyState(isDark)
                      : RefreshIndicator(
                          onRefresh: _loadCustomers,
                          color: AdminColors.accent,
                          child: ListView.builder(
                            // ── AlwaysScrollableScrollPhysics ensures
                            //    pull-to-refresh works even with few items ──
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: _filteredCustomers.length,
                            itemBuilder: (context, index) => _buildCustomerCard(
                              _filteredCustomers[index],
                              isDark,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(14)),
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
        controller: _searchController,
        onChanged: (_) => setState(() => _applyFilters()),
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: 'Search name, company, email, phone...',
          hintStyle: TextStyle(
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            size: 22,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _applyFilters());
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 18,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: isDark ? Brand.darkCard : Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── FILTER CHIPS ──────────────────────────────────────────

  Widget _buildFilterChips(bool isDark) {
    final filters = [
      _FilterItem('all', 'All', _customers.length, Icons.people_rounded,
          AdminColors.primary),
      _FilterItem('with_machines', 'Machines', _withMachinesCount,
          Icons.precision_manufacturing_rounded, AdminColors.accent),
      _FilterItem('with_tickets', 'Tickets', _withTicketsCount,
          Icons.support_agent_rounded, AdminColors.warning),
      _FilterItem('with_inquiries', 'Inquiries', _withInquiriesCount,
          Icons.mail_rounded, AdminColors.info),
      _FilterItem('active', 'Active', _activeCount, Icons.flash_on_rounded,
          const Color(0xFF8E24AA)),
      _FilterItem('new', 'New', _newThisWeekCount, Icons.fiber_new_rounded,
          AdminColors.success),
    ];

    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _filterType == filter.key;

          return GestureDetector(
            onTap: () => setState(() {
              _filterType = filter.key;
              _applyFilters();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? filter.color
                    : (isDark ? Brand.darkCard : Colors.white),
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                  color: isSelected
                      ? filter.color
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: filter.color.withAlpha(75),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  filter.key == 'with_tickets'
                      ? IcChatGearIcon(
                          size: 14,
                          color: isSelected ? Colors.white : filter.color,
                        )
                      : Icon(
                          filter.icon,
                          size: 14,
                          color: isSelected ? Colors.white : filter.color,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withAlpha(63)
                          : filter.color.withAlpha(25),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Text(
                      '${filter.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : filter.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── RESULTS COUNT ─────────────────────────────────────────

  Widget _buildResultsCount(bool isDark) {
    if (_isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text(
            '${_filteredCustomers.length} ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
            ),
          ),
          Text(
            _filteredCustomers.length == _customers.length
                ? 'customers'
                : 'of ${_customers.length} customers',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _showSortOptions(isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getSortLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CUSTOMER CARD ─────────────────────────────────────────

  Widget _buildCustomerCard(Map<String, dynamic> customer, bool isDark) {
    final name = customer['full_name'] as String? ?? 'Unknown';
    final company = customer['company_name'] as String? ?? '';
    final machineCount = (customer['machine_count'] ?? 0) as int;
    final ticketCount = (customer['ticket_count'] ?? 0) as int;
    final inquiryCount = (customer['inquiry_count'] ?? 0) as int;
    final openTickets = (customer['open_ticket_count'] ?? 0) as int;
    final wonDeals = (customer['won_deals'] ?? 0) as int;
    final photoUrl = customer['profile_photo'] as String?;

    DateTime? createdAt;
    try {
      createdAt = DateTime.parse(customer['created_at'] as String);
    } catch (_) {
      createdAt = null;
    }

    final daysAgo =
        createdAt != null ? DateTime.now().difference(createdAt).inDays : 999;
    final timeAgo =
        createdAt != null ? TimeUtils.getTimeAgo(createdAt) : 'Unknown';
    final isNew = daysAgo < 7;
    final hasOpenTickets = openTickets > 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CustomerDetailPage(customerId: customer['id'] as String),
          ),
        ).then((_) => _loadCustomers());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Top Row: Avatar + Name + Badge ──
              Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AdminColors.primary.withAlpha(isDark ? 38 : 20),
                              AdminColors.accent.withAlpha(isDark ? 38 : 20),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(Brand.r(15)),
                        ),
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(Brand.r(15)),
                                child: CachedNetworkImage(
                                  imageUrl: photoUrl,
                                  fit: BoxFit.cover,
                                  width: 50,
                                  height: 50,
                                  placeholder: (_, __) => Center(
                                    child: Text(
                                      _getInitials(name),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Brand.darkIconActive
                                            : AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(
                                      _getInitials(name),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Brand.darkIconActive
                                            : AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  _getInitials(name),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Brand.darkIconActive
                                        : AdminColors.primary,
                                  ),
                                ),
                              ),
                      ),
                      if (hasOpenTickets)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AdminColors.warning,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Brand.darkCard : Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (company.isNotEmpty) ...[
                              Icon(
                                Icons.business_rounded,
                                size: 12,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  company,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ── Priority badge — differentiated colors ──
                  if (isNew)
                    _buildBadge('NEW', AdminColors.accent, isDark)
                  else if (wonDeals > 0)
                    // Won deals: green to distinguish from NEW
                    _buildBadge('$wonDeals WON', Brand.lightGreen, isDark)
                  else if (hasOpenTickets)
                    _buildBadge(
                        '$openTickets OPEN', AdminColors.warning, isDark)
                  else
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color:
                            isDark ? Brand.darkIconActive : AdminColors.primary,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Contact Row ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 14,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        customer['email'] as String? ?? 'N/A',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (customer['phone_number'] != null) ...[
                      Container(
                        width: 1,
                        height: 16,
                        color:
                            isDark ? Brand.darkBorderLight : Brand.borderLight,
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.phone_outlined,
                        size: 14,
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          customer['phone_number'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : const Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if ((customer['province'] != null &&
                      (customer['province'] as String).isNotEmpty) ||
                  (customer['district'] != null &&
                      (customer['district'] as String).isNotEmpty) ||
                  customer['connector_id'] != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (customer['province'] != null &&
                        (customer['province'] as String).isNotEmpty)
                      _metaChip(Icons.map_rounded,
                          customer['province'] as String, isDark),
                    if (customer['district'] != null &&
                        (customer['district'] as String).isNotEmpty)
                      _metaChip(Icons.location_on_outlined,
                          customer['district'] as String, isDark),
                    if (customer['connector_id'] != null)
                      _metaChip(
                        Icons.support_agent_rounded,
                        _connectorsById[customer['connector_id']]
                                ?['full_name']
                                ?.toString() ??
                            'Connector',
                        isDark,
                        emphasised: true,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // ── Activity Stats Row ──
              Row(
                children: [
                  _buildActivityChip(
                    Icons.precision_manufacturing_rounded,
                    '$machineCount',
                    AdminColors.primary,
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildActivityChip(
                    Icons.support_agent_rounded,
                    '$ticketCount',
                    AdminColors.warning,
                    isDark,
                    iconWidget: const IcChatGearIcon(
                        color: AdminColors.warning, size: 12),
                  ),
                  const SizedBox(width: 8),
                  _buildActivityChip(
                    Icons.mail_rounded,
                    '$inquiryCount',
                    AdminColors.info,
                    isDark,
                  ),
                  const Spacer(),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withAlpha(isDark ? 38 : 20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.visibility_rounded,
                      size: 16,
                      color:
                          isDark ? Brand.darkIconActive : AdminColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 38 : 30),
        borderRadius: BorderRadius.circular(Brand.r(10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildActivityChip(
      IconData icon, String value, Color color, bool isDark,
      {Widget? iconWidget}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 31 : 20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget ?? Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Small chip surfacing province/district/connector under each card.
  // `emphasised` flag styles the connector pill in the accent colour so
  // it stands out from the location chips.
  Widget _metaChip(IconData icon, String label, bool isDark,
      {bool emphasised = false}) {
    final color = emphasised
        ? AdminColors.accent
        : (isDark ? Brand.darkTextSecondary : Brand.subtleLight);
    final bg = emphasised
        ? AdminColors.accent.withAlpha(isDark ? 38 : 26)
        : (isDark
            ? Brand.darkCardElevated
            : const Color(0xFFF4F6FA));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: emphasised
            ? Border.all(color: AdminColors.accent.withAlpha(64))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
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
              color: AdminColors.primary.withAlpha(isDark ? 38 : 20),
              borderRadius: BorderRadius.circular(Brand.r(18)),
            ),
            child: Center(
              child: CircularProgressIndicator(
                color: isDark ? Brand.darkIconActive : AdminColors.primary,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading customers...',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    final hasFilters =
        _searchController.text.isNotEmpty || _filterType != 'all';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AdminColors.primary.withAlpha(isDark ? 26 : 15),
                borderRadius: BorderRadius.circular(Brand.r(24)),
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 40,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilters ? 'No customers found' : 'No customers yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your search or filters'
                  : 'Customers will appear here after signup',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _filterType = 'all';
                    _applyFilters();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminColors.accent.withAlpha(25),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: const Text(
                    'Clear Filters',
                    style: TextStyle(
                      color: AdminColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── EXPORT TO EXCEL (v24) ─────────────────────────────────
  Future<void> _exportToExcel() async {
    if (_filteredCustomers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export with current filters.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing Excel export…')),
    );
    final path = await ExportService.instance.exportCustomers(_filteredCustomers);
    if (!mounted) return;
    ExportService.showResult(context, path);
  }

  // ─── SORT BOTTOM SHEET ─────────────────────────────────────

  void _showSortOptions(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        // ── Use sheetCtx for theme — consistent with dark mode ──
        final sheetDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: sheetDark ? Brand.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetDark
                      ? Colors.white.withAlpha(26)
                      : Colors.black.withAlpha(26),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sort Customers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      sheetDark ? Brand.darkTextPrimary : AdminColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              _buildSortOption('newest', 'Newest First', Icons.schedule_rounded,
                  sheetCtx, sheetDark),
              _buildSortOption('oldest', 'Oldest First', Icons.history_rounded,
                  sheetCtx, sheetDark),
              _buildSortOption('name_az', 'Name A → Z',
                  Icons.sort_by_alpha_rounded, sheetCtx, sheetDark),
              _buildSortOption('most_machines', 'Most Machines',
                  Icons.precision_manufacturing_rounded, sheetCtx, sheetDark),
              _buildSortOption('most_tickets', 'Most Tickets',
                  Icons.support_agent_rounded, sheetCtx, sheetDark,
                  useChatGearIcon: true),
              _buildSortOption('most_inquiries', 'Most Inquiries',
                  Icons.mail_rounded, sheetCtx, sheetDark),
              _buildSortOption('by_province', 'By Province',
                  Icons.map_rounded, sheetCtx, sheetDark),
              _buildSortOption('by_district', 'By District',
                  Icons.location_on_outlined, sheetCtx, sheetDark),
              _buildSortOption('by_connector', 'By Connector',
                  Icons.support_agent_rounded, sheetCtx, sheetDark),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Group by',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: sheetDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _groupChip('none', 'None', sheetCtx, sheetDark),
                  _groupChip(
                      'province', 'Province', sheetCtx, sheetDark),
                  _groupChip(
                      'district', 'District', sheetCtx, sheetDark),
                  _groupChip(
                      'connector', 'Connector', sheetCtx, sheetDark),
                ],
              ),
              const SizedBox(height: 16),
              if (_groupBy != 'none')
                _buildGroupValuePicker(sheetCtx, sheetDark),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _groupChip(
      String value, String label, BuildContext sheetCtx, bool isDark) {
    final selected = _groupBy == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _groupBy = value;
          _groupValue = null; // reset sub-filter when switching axis
          _applyFilters();
        });
        if (value == 'connector') {
          // Make sure connector names + ids are ready for the value picker.
          _ensureConnectorsLoaded();
        }
        // Close + reopen so the sheet re-renders with the value picker.
        Navigator.pop(sheetCtx);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        _showSortOptions(isDark);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.primary.withAlpha(isDark ? 51 : 26)
              : (isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: selected
                ? AdminColors.primary
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected
                ? (isDark ? Brand.darkIconActive : AdminColors.primary)
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupValuePicker(BuildContext sheetCtx, bool isDark) {
    // Build distinct values from loaded customers based on current axis.
    List<String> values;
    switch (_groupBy) {
      case 'province':
        values = _customers
            .map((c) => (c['province'] as String?) ?? '')
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        break;
      case 'district':
        values = _customers
            .map((c) => (c['district'] as String?) ?? '')
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        break;
      case 'connector':
        // For connectors, "value" is the connector_id; use lookup map for the label.
        values = _customers
            .map((c) => (c['connector_id'] as String?) ?? '')
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList();
        break;
      default:
        return const SizedBox.shrink();
    }

    String labelFor(String v) {
      if (_groupBy == 'connector') {
        return _connectorsById[v]?['full_name']?.toString() ?? v;
      }
      return v;
    }

    final showUnassignedChip = _groupBy == 'connector' &&
        _customers.any((c) => (c['connector_id'] as String?) == null);

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _valueChip(null, 'All', sheetCtx, isDark),
          if (showUnassignedChip)
            _valueChip('__none__', 'No connector', sheetCtx, isDark),
          ...values.map((v) => _valueChip(v, labelFor(v), sheetCtx, isDark)),
        ],
      ),
    );
  }

  Widget _valueChip(
      String? value, String label, BuildContext sheetCtx, bool isDark) {
    final selected = _groupValue == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _groupValue = value;
          _applyFilters();
        });
        Navigator.pop(sheetCtx);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.accent.withAlpha(isDark ? 51 : 26)
              : (isDark ? Brand.darkCardElevated : const Color(0xFFEFF5E3)),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: Border.all(
            color: selected
                ? AdminColors.accent
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? AdminColors.accent
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(
    String value,
    String label,
    IconData icon,
    BuildContext sheetCtx,
    bool isDark, {
    bool useChatGearIcon = false,
  }) {
    final isSelected = _sortBy == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = value;
          _applyFilters();
        });
        Navigator.pop(sheetCtx);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AdminColors.primary.withAlpha(isDark ? 26 : 15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: isSelected
              ? Border.all(
                  color: AdminColors.primary.withAlpha(38),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AdminColors.primary.withAlpha(isDark ? 38 : 25)
                    : (isDark
                        ? Brand.darkCardElevated
                        : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: useChatGearIcon
                  ? IcChatGearIcon(
                      size: 18,
                      color: isSelected
                          ? (isDark
                              ? Brand.darkIconActive
                              : AdminColors.primary)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    )
                  : Icon(
                      icon,
                      size: 18,
                      color: isSelected
                          ? (isDark
                              ? Brand.darkIconActive
                              : AdminColors.primary)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Brand.darkIconActive : AdminColors.primary)
                    : (isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF475569)),
              ),
            ),
            const Spacer(),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AdminColors.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── HELPER CLASS ────────────────────────────────────────────

class _FilterItem {
  final String key;
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _FilterItem(this.key, this.label, this.count, this.icon, this.color);
}
