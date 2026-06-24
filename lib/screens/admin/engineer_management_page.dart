// lib/screens/admin/engineer_management_page.dart
// Fixed: .withOpacity() → .withAlpha() throughout,
//   MediaQuery sheetCtx, mounted guards, AlwaysScrollableScrollPhysics,
//   AdminColors.warning, error feedback on outer catch

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../utils/string_utils.dart';

// ── Engineer-specific accent (file-level const, not in Brand) ─
const Color _engAccent = Brand.cyanAccent;
const Color _engAccentDark = Brand.cyanAccentDark;

const _allSpecializations = [
  'Digital Printers',
  'Eco Solvent Printers',
  'UV Printers',
  'CNC Machines',
  'Laser Cutters',
  'CO2 Lasers',
  'Fiber Lasers',
  'Finishing Equipment',
  'General Support',
  'Installation',
  'Calibration',
];

// ══════════════════════════════════════════════════════════════
//  PAGE
// ══════════════════════════════════════════════════════════════
class EngineerManagementPage extends StatefulWidget {
  const EngineerManagementPage({super.key});

  @override
  State<EngineerManagementPage> createState() => _EngineerManagementPageState();
}

class _EngineerManagementPageState extends State<EngineerManagementPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _engineers = [];
  List<Map<String, dynamic>> _filtered = [];
  String _search = '';
  String _statusFilter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── DATA ─────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> engList;
      try {
        final rpcResult =
            await SupabaseConfig.client.rpc('get_engineers_with_stats');
        if (!mounted) return;
        if (rpcResult is List && rpcResult.isNotEmpty) {
          engList = (rpcResult).map((e) {
            final m = e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map);
            return {
              ...m,
              'ticket_counts': {
                'total': m['ticket_total'] ?? 0,
                'active': m['ticket_active'] ?? 0,
                'resolved': m['ticket_resolved'] ?? 0,
              },
            };
          }).toList();
        } else {
          engList = await _loadFallback();
          if (!mounted) return;
        }
      } catch (_) {
        engList = await _loadFallback();
        if (!mounted) return;
      }

      setState(() {
        _engineers = engList;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load engineers error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Failed to load engineers. Please retry.', isError: true);
    }
  }

  Future<List<Map<String, dynamic>>> _loadFallback() async {
    final engineers = await SupabaseConfig.client
        .from('users')
        .select('*')
        .eq('role', 'engineer')
        .order('full_name', ascending: true);

    final engList = List<Map<String, dynamic>>.from(engineers as List);
    final ids = engList.map((e) => e['id'] as String).toList();

    final Map<String, Map<String, int>> ticketCounts = {};

    if (ids.isNotEmpty) {
      final tickets = await SupabaseConfig.client
          .from('service_tickets')
          .select('assigned_to, status')
          .inFilter('assigned_to', ids)
          .eq('is_deleted', false);

      final ticketList = List<Map<String, dynamic>>.from(tickets as List);

      for (final id in ids) {
        final tks = ticketList.where((t) => t['assigned_to'] == id).toList();
        ticketCounts[id] = {
          'total': tks.length,
          'active': tks
              .where((t) => [
                    'open',
                    'assigned',
                    'in_progress',
                    'waiting_customer',
                  ].contains(t['status']))
              .length,
          'resolved': tks
              .where((t) => ['resolved', 'closed'].contains(t['status']))
              .length,
        };
      }
    }

    // ── Spread copy — NO direct mutation ──
    return engList.map((e) {
      final id = e['id'] as String;
      return {
        ...e,
        'ticket_counts':
            ticketCounts[id] ?? {'total': 0, 'active': 0, 'resolved': 0},
      };
    }).toList();
  }

  void _applyFilters() {
    final q = _search.toLowerCase();
    _filtered = _engineers.where((e) {
      final name = (e['full_name'] as String? ?? '').toLowerCase();
      final email = (e['email'] as String? ?? '').toLowerCase();
      final avail = e['availability_status'] as String? ?? 'offline';
      if (q.isNotEmpty && !name.contains(q) && !email.contains(q)) {
        return false;
      }
      if (_statusFilter != 'all' && avail != _statusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color _availColor(String s) {
    switch (s) {
      case 'available':
        return Brand.lightGreenBright;
      case 'busy':
        return AdminColors.warning;
      default:
        return Brand.darkTextSecondary;
    }
  }

  Future<void> _doInviteEngineer({
    required String name,
    required String username,
    required String password,
    required String phone,
    required List<String> specs,
    required String bio,
  }) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) {
      throw Exception('Session expired, please log in again');
    }

    final response = await SupabaseConfig.client.functions.invoke(
      'create-engineer',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {
        'username': username,
        'full_name': name,
        'password': password,
        'phone_number': phone.isEmpty ? null : phone,
        'specializations': specs,
        'engineer_bio': bio.isEmpty ? null : bio,
      },
    );

    final data = response.data;
    if (data is Map && data['success'] == true) return;

    final errMsg = (data is Map ? data['error']?.toString() : null) ??
        'Failed to create engineer (status ${response.status})';

    if (response.status == 403) throw Exception('Only admins can create engineers');
    if (response.status == 409) throw Exception('Username "$username" is already taken');
    throw Exception(errMsg);
  }


  void _showSnackBar(
    String message, {
    bool isError = false,
    Color? color,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? AdminColors.error : (color ?? Brand.lightGreenBright),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: actionLabel != null ? 6 : (isError ? 4 : 3)),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('session expired') || msg.contains('log in again')) {
      return 'Session expired, please log in again.';
    }
    if (msg.contains('only admins')) {
      return 'Only admins can invite engineers.';
    }
    if (msg.contains('network') || msg.contains('socketexception')) {
      return 'Network error. Check your connection.';
    }
    if (msg.contains('unauthorized') || msg.contains('permission')) {
      return 'You do not have permission to invite engineers.';
    }
    if (msg.contains('profile insert failed') ||
        msg.contains('upsert failed')) {
      return 'Engineer account created but profile save failed. '
          'Please check the engineer list or try again.';
    }
    if (msg.contains('admin session lost')) {
      return 'Engineer was created but your session was lost. '
          'Please log in again.';
    }
    // Show a shortened version of the real error for debugging
    final raw = e.toString();
    final short = raw.length > 100
        ? '${raw.substring(0, 100)}…'
        : raw;
    return 'Error: $short';
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        appBar: DsPageHeader(
          title: 'Engineer Team',
          subtitle: '${_engineers.length} registered',
          accent: HeroAccent.navy,
          actions: [
            IconButton(icon: const Icon(Icons.person_add_outlined, color: Colors.white), onPressed: () => _showAddEngineerSheet(_isDark)),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(isDark),
              _buildFilterChips(isDark),
              _buildSummaryRow(isDark),
              Expanded(
                child: _isLoading
                    ? _skeleton(isDark)
                    : RefreshIndicator(
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                        backgroundColor: Brand.surface(isDark),
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? _emptyState(isDark)
                            : ListView.builder(
                                // ── AlwaysScrollable ensures
                                //    pull-to-refresh works
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _engineerCard(_filtered[i], isDark),
                              ),
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(isDark),
      ),
    );
  }

  // ─── SEARCH BAR ───────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
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
            _search = v;
            _applyFilters();
          }),
          style: TextStyle(
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Search by name or email...',
            hintStyle: TextStyle(
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              size: 20,
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _search = '';
                      _applyFilters();
                    }),
                  )
                : null,
            enabledBorder: InputBorder.none,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Brand.r(14)),
              borderSide: BorderSide(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          ),
        ),
      ),
    );
  }

  // ─── FILTER CHIPS ─────────────────────────────────────────
  Widget _buildFilterChips(bool isDark) {
    final filters = [
      const _FilterChip('all', 'All', null),
      const _FilterChip('available', 'Available', Brand.lightGreenBright),
      const _FilterChip('busy', 'Busy', AdminColors.warning),
      _FilterChip('offline', 'Offline', Brand.darkTextSecondary),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isSel = _statusFilter == f.key;
            final c =
                f.color ?? (isDark ? Brand.darkIconActive : Brand.royalBlue);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  _statusFilter = f.key;
                  _applyFilters();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    // ✅ .withAlpha() — was .withOpacity()
                    color: isSel
                        ? c.withAlpha(isDark ? 38 : 31)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                    border: Border.all(
                      color: isSel
                          ? c.withAlpha(128)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (f.color != null) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSel
                              ? c
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── SUMMARY ROW ──────────────────────────────────────────
  Widget _buildSummaryRow(bool isDark) {
    final available =
        _engineers.where((e) => e['availability_status'] == 'available').length;
    final busy =
        _engineers.where((e) => e['availability_status'] == 'busy').length;
    final offline =
        _engineers.where((e) => e['availability_status'] == 'offline').length;
    final totalActive = _engineers.fold<int>(0, (s, e) {
      final c = e['ticket_counts'] as Map<String, dynamic>? ?? {};
      return s + ((c['active'] as num?)?.toInt() ?? 0);
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _sumCard('$available', 'Available', Brand.lightGreenBright, isDark),
          const SizedBox(width: 8),
          _sumCard('$busy', 'Busy', AdminColors.warning, isDark),
          const SizedBox(width: 8),
          _sumCard('$offline', 'Offline', Brand.darkTextSecondary, isDark),
          const SizedBox(width: 8),
          _sumCard('$totalActive', 'Active Tix', Brand.darkIconActive, isDark),
        ],
      ),
    );
  }

  Widget _sumCard(String val, String label, Color c, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: Border.all(
            color: isDark ? Brand.darkBorder : c.withAlpha(31),
          ),
        ),
        child: Column(
          children: [
            Text(
              val,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── ENGINEER CARD ────────────────────────────────────────
  Widget _engineerCard(Map<String, dynamic> eng, bool isDark) {
    final name = eng['full_name'] as String? ?? '';
    final email = eng['email'] as String? ?? '';
    final phone = eng['phone_number'] as String? ?? '';
    final photo = eng['profile_photo'] as String?;
    final avail = eng['availability_status'] as String? ?? 'offline';
    final specs = (eng['specializations'] as List?)?.cast<String>() ?? [];
    final rating = (eng['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final counts = eng['ticket_counts'] as Map<String, dynamic>? ?? {};
    final aColor = _availColor(avail);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: avatar + name + availability + menu ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_engAccent, _engAccentDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ClipOval(
                        child: photo != null && photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                width: 52,
                                height: 52,
                                placeholder: (_, __) => Center(
                                  child: Text(
                                    StringUtils.getInitials(name),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    StringUtils.getInitials(name),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  StringUtils.getInitials(name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: aColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Brand.surface(isDark),
                          width: 2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        // ✅ .withAlpha() — was .withOpacity()
                        color: aColor.withAlpha(isDark ? 31 : 26),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        border: Border.all(color: aColor.withAlpha(77)),
                      ),
                      child: Text(
                        avail.toUpperCase(),
                        style: TextStyle(
                          color: aColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _engineerMenu(eng, isDark),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(
              color: isDark ? Brand.darkBorder : Brand.borderLight,
              height: 1,
            ),
            const SizedBox(height: 12),

            // ── Ticket stats ──
            Row(
              children: [
                _miniStat(
                  '${(counts['active'] as num?)?.toInt() ?? 0}',
                  'Active',
                  Brand.darkIconActive,
                  isDark,
                ),
                const SizedBox(width: 8),
                _miniStat(
                  '${(counts['resolved'] as num?)?.toInt() ?? 0}',
                  'Resolved',
                  Brand.lightGreenBright,
                  isDark,
                ),
                const SizedBox(width: 8),
                _miniStat(
                  '${(counts['total'] as num?)?.toInt() ?? 0}',
                  'Total',
                  Brand.darkTextSecondary,
                  isDark,
                ),
                const Spacer(),
                if (rating > 0)
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AdminColors.warning, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AdminColors.warning,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // ── Specializations ──
            if (specs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: specs
                    .take(4)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            // ✅ .withAlpha() — was .withOpacity()
                            color: _engAccent.withAlpha(isDark ? 26 : 20),
                            borderRadius: BorderRadius.circular(Brand.r(10)),
                            border: Border.all(color: _engAccent.withAlpha(51)),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              color: _engAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ))
                    .followedBy(
                      specs.length > 4
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight)
                                      .withAlpha(26),
                                  borderRadius: BorderRadius.circular(Brand.r(10)),
                                ),
                                child: Text(
                                  '+${specs.length - 4} more',
                                  style: TextStyle(
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ]
                          : [],
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String val, String label, Color c, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // ✅ .withAlpha() — was .withOpacity()
        color: c.withAlpha(isDark ? 26 : 18),
        borderRadius: BorderRadius.circular(Brand.r(8)),
      ),
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _engineerMenu(Map<String, dynamic> eng, bool isDark) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        size: 20,
      ),
      color: Brand.surface(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(16))),
      itemBuilder: (_) => [
        _menuItem('edit', 'Edit Details', Icons.edit_rounded,
            Brand.darkIconActive, isDark),
        _menuItem('remove', 'Remove Engineer', Icons.person_remove_rounded,
            AdminColors.error, isDark),
      ],
      onSelected: (action) {
        if (action == 'edit') _showEditSheet(eng, isDark);
        if (action == 'remove') _confirmRemove(eng, isDark);
      },
    );
  }

  PopupMenuItem<String> _menuItem(
    String val,
    String label,
    IconData icon,
    Color c,
    bool isDark,
  ) {
    return PopupMenuItem(
      value: val,
      child: Row(
        children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FAB ──────────────────────────────────────────────────
  Widget _buildFAB(bool isDark) {
    return FloatingActionButton.extended(
      onPressed: () => _showAddEngineerSheet(isDark),
      backgroundColor: Colors.transparent,
      elevation: 0,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      label: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_engAccent, _engAccentDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          boxShadow: [
            BoxShadow(
              color: _engAccent.withAlpha(115),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Add Engineer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  ADD ENGINEER BOTTOM SHEET
  // ══════════════════════════════════════════════════════════
  void _showAddEngineerSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEngineerSheet(
        isDark: isDark,
        doInvite: _doInviteEngineer,
        friendlyError: _friendlyError,
        onSuccess: (username) {
          if (!mounted) return;
          _showSnackBar('Engineer "$username" created successfully');
          _load();
        },
      ),
    );
  }

  // ── Legacy add-engineer sheet body removed — now provided by
  // ─── EDIT SHEET ───────────────────────────────────────────
  void _showEditSheet(Map<String, dynamic> eng, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditEngineerSheet(
        isDark: isDark,
        engineer: eng,
        onSaved: () {
          if (!mounted) return;
          _showSnackBar('Engineer updated successfully');
          _load();
        },
      ),
    );
  }

  // ─── REMOVE ENGINEER ──────────────────────────────────────
  void _confirmRemove(Map<String, dynamic> eng, bool isDark) {
    final name = eng['full_name'] as String? ?? 'this engineer';
    final counts = eng['ticket_counts'] as Map<String, dynamic>? ?? {};
    final activeCount = (counts['active'] as num?)?.toInt() ?? 0;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Brand.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: Text(
          'Demote to Customer',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This changes $name\'s account role from engineer to '
              'customer. They will lose engineer access immediately '
              'and the app will treat them as a regular customer '
              'until an admin sets their role back to engineer.',
              style: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            if (activeCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // ✅ AdminColors.warning — no hardcoded orange
                  color: AdminColors.warning.withAlpha(isDark ? 26 : 20),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  border: Border.all(color: AdminColors.warning.withAlpha(77)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AdminColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$activeCount active ticket'
                        '${activeCount > 1 ? 's' : ''} '
                        'will need to be reassigned.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AdminColors.warning
                              : AdminColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await SupabaseConfig.client
                    .from('users')
                    .update({'role': 'customer'}).eq('id', eng['id'] as String);
                if (!mounted) return;
                _showSnackBar(
                  '$name demoted to customer',
                  color: AdminColors.warning,
                  actionLabel: 'Undo',
                  onAction: () async {
                    try {
                      await SupabaseConfig.client
                          .from('users')
                          .update({'role': 'engineer'}).eq(
                              'id', eng['id'] as String);
                      if (!mounted) return;
                      _showSnackBar('$name restored as engineer');
                      _load();
                    } catch (e) {
                      if (!mounted) return;
                      _showSnackBar('Failed to undo', isError: true);
                    }
                  },
                );
                _load();
              } catch (e) {
                if (!mounted) return;
                _showSnackBar(
                  'Failed to remove engineer',
                  isError: true,
                );
              }
            },
            child: const Text(
              'Demote',
              style: TextStyle(
                color: AdminColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY / SKELETON ─────────────────────────────────────
  Widget _emptyState(bool isDark) {
    // ── Wrap in scrollable so RefreshIndicator works ──
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 400,
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
                    borderRadius: BorderRadius.circular(Brand.r(24)),
                  ),
                  child: Icon(
                    Icons.engineering_rounded,
                    size: 40,
                    color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No engineers found',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Add Engineer" to invite your first engineer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeleton(bool isDark) {
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
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            sk(52, 52, 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sk(140, 14, 7),
                  const SizedBox(height: 7),
                  sk(180, 11, 5),
                  const SizedBox(height: 12),
                  sk(double.infinity, 10, 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── HELPER CLASS ─────────────────────────────────────────────
class _FilterChip {
  final String key;
  final String label;
  final Color? color;

  const _FilterChip(this.key, this.label, this.color);
}

// ══════════════════════════════════════════════════════════════
//  SHARED SHEET HELPERS (top-level so the StatefulWidget sheets
//  below can use them without depending on the page State).
// ══════════════════════════════════════════════════════════════

Widget _sectionTitle(String title, IconData icon, bool isDark) {
  return Row(
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _engAccent.withAlpha(isDark ? 31 : 26),
          borderRadius: BorderRadius.circular(Brand.r(9)),
        ),
        child: Icon(icon, color: _engAccent, size: 16),
      ),
      const SizedBox(width: 10),
      Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
      ),
    ],
  );
}

Widget _sheetTextField(
  TextEditingController ctrl,
  String label,
  IconData icon,
  bool isDark, {
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  bool obscureText = false,
  Widget? suffixIcon,
  List<TextInputFormatter>? inputFormatters,
}) {
  return TextFormField(
    controller: ctrl,
    keyboardType: keyboardType,
    validator: validator,
    obscureText: obscureText,
    inputFormatters: inputFormatters,
    style: TextStyle(
      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
      fontSize: 14,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
      ),
      prefixIcon: Icon(
        icon,
        color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        size: 20,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.r(14)),
        borderSide:
            BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.r(14)),
        borderSide:
            BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.r(14)),
        borderSide: const BorderSide(color: _engAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.r(14)),
        borderSide: const BorderSide(color: AdminColors.error),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
//  ADD ENGINEER SHEET (proper StatefulWidget)
//
//  Owning all controllers + form key in a State subclass means
//  Flutter disposes them automatically *after* the widget is fully
//  unmounted — eliminating the "TextEditingController used after
//  disposed", "_dependents.isEmpty", "Looking up a deactivated
//  widget's ancestor", and "Duplicate GlobalKeys" runtime errors
//  that the previous closure-scoped + .whenComplete() approach
//  produced.
// ══════════════════════════════════════════════════════════════

typedef _InviteFn = Future<void> Function({
  required String name,
  required String username,
  required String password,
  required String phone,
  required List<String> specs,
  required String bio,
});

class _AddEngineerSheet extends StatefulWidget {
  final bool isDark;
  final _InviteFn doInvite;
  final String Function(Object) friendlyError;
  final void Function(String username) onSuccess;

  const _AddEngineerSheet({
    required this.isDark,
    required this.doInvite,
    required this.friendlyError,
    required this.onSuccess,
  });

  @override
  State<_AddEngineerSheet> createState() => _AddEngineerSheetState();
}

class _AddEngineerSheetState extends State<_AddEngineerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final List<String> _selectedSpecs = [];
  bool _isSending = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final username = _usernameCtrl.text.trim().toLowerCase();

    setState(() => _isSending = true);
    try {
      await widget.doInvite(
        name: _nameCtrl.text.trim(),
        username: username,
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim(),
        specs: _selectedSpecs,
        bio: _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      navigator.pop();
      widget.onSuccess(username);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.friendlyError(e),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ]),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(12)),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height;

    return Container(
      height: height * 0.92,
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkBorderLight : AdminColors.textSecondary,
              borderRadius: BorderRadius.circular(Brand.r(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _engAccent.withAlpha(isDark ? 31 : 26),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: _engAccent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add New Engineer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      Text(
                        'Username + password — no email required',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 24,
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                        'Basic Information', Icons.person_rounded, isDark),
                    const SizedBox(height: 14),
                    _sheetTextField(
                      _nameCtrl,
                      'Full Name *',
                      Icons.person_outline_rounded,
                      isDark,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _sheetTextField(
                      _usernameCtrl,
                      'Username *',
                      Icons.alternate_email_rounded,
                      isDark,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Username is required';
                        }
                        if (!RegExp(r'^[a-z0-9._]+$').hasMatch(v.trim())) {
                          return 'Lowercase letters, numbers, dots and underscores only';
                        }
                        if (v.trim().length < 3) return 'At least 3 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _sheetTextField(
                      _passwordCtrl,
                      'Password *',
                      Icons.lock_outline_rounded,
                      isDark,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 18,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 8) return 'At least 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _sheetTextField(
                      _phoneCtrl,
                      'Phone Number',
                      Icons.phone_outlined,
                      isDark,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Specializations',
                        Icons.engineering_rounded, isDark),
                    const SizedBox(height: 6),
                    Text(
                      'Select all that apply',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allSpecializations.map((s) {
                        final isSel = _selectedSpecs.contains(s);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isSel) {
                              _selectedSpecs.remove(s);
                            } else {
                              _selectedSpecs.add(s);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? _engAccent.withAlpha(isDark ? 38 : 31)
                                  : (isDark
                                      ? Brand.darkCardElevated
                                      : Brand.royalBlueSurface),
                              borderRadius: BorderRadius.circular(Brand.r(20)),
                              border: Border.all(
                                color: isSel
                                    ? _engAccent.withAlpha(128)
                                    : (isDark
                                        ? Brand.darkBorder
                                        : Brand.borderLight),
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSel) ...[
                                  const Icon(Icons.check_rounded,
                                      color: _engAccent, size: 12),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSel
                                        ? _engAccent
                                        : (isDark
                                            ? Brand.darkTextSecondary
                                            : Brand.subtleLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Bio (Optional)',
                        Icons.person_pin_rounded, isDark),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        border: Border.all(
                          color: isDark
                              ? Brand.darkBorder
                              : Brand.borderLight,
                        ),
                      ),
                      child: TextField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Short introduction about this engineer...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontSize: 13,
                          ),
                          enabledBorder: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            borderSide: BorderSide(
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue,
                                width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _engAccent.withAlpha(isDark ? 20 : 15),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        border:
                            Border.all(color: _engAccent.withAlpha(51)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: _engAccent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The account is created immediately. '
                              'Share the username and password with the engineer '
                              'via WhatsApp or phone. No email needed.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(24, 12, 24, viewInsets + 16),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              border: Border(
                top: BorderSide(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                ),
              ),
            ),
            child: _isSending
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: isDark ? _engAccent : Brand.royalBlue,
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'Creating account...',
                            style: TextStyle(
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _submit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_engAccentDark, _engAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: _engAccent.withAlpha(89),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Create Engineer Account',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  EDIT ENGINEER SHEET (proper StatefulWidget)
// ══════════════════════════════════════════════════════════════

class _EditEngineerSheet extends StatefulWidget {
  final bool isDark;
  final Map<String, dynamic> engineer;
  final VoidCallback onSaved;

  const _EditEngineerSheet({
    required this.isDark,
    required this.engineer,
    required this.onSaved,
  });

  @override
  State<_EditEngineerSheet> createState() => _EditEngineerSheetState();
}

class _EditEngineerSheetState extends State<_EditEngineerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _bioCtrl;
  late final List<String> _selectedSpecs;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.engineer['full_name'] ?? '');
    _phoneCtrl =
        TextEditingController(text: widget.engineer['phone_number'] ?? '');
    _bioCtrl =
        TextEditingController(text: widget.engineer['engineer_bio'] ?? '');
    _selectedSpecs = List<String>.from(
        (widget.engineer['specializations'] as List?)?.cast<String>() ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    try {
      await SupabaseConfig.client.from('users').update({
        'full_name': _nameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'engineer_bio': _bioCtrl.text.trim(),
        'specializations': _selectedSpecs,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.engineer['id'] as String);

      if (!mounted) return;
      navigator.pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(12)),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height;

    return Container(
      height: height * 0.88,
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkBorderLight : AdminColors.textSecondary,
              borderRadius: BorderRadius.circular(Brand.r(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Text(
                  'Edit Engineer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : Brand.royalBlueDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 20,
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetTextField(
                      _nameCtrl,
                      'Full Name *',
                      Icons.person_outline_rounded,
                      isDark,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _sheetTextField(
                      _phoneCtrl,
                      'Phone Number',
                      Icons.phone_outlined,
                      isDark,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Specializations',
                        Icons.engineering_rounded, isDark),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allSpecializations.map((s) {
                        final isSel = _selectedSpecs.contains(s);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isSel) {
                              _selectedSpecs.remove(s);
                            } else {
                              _selectedSpecs.add(s);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? _engAccent.withAlpha(38)
                                  : (isDark
                                      ? Brand.darkCardElevated
                                      : Brand.royalBlueSurface),
                              borderRadius: BorderRadius.circular(Brand.r(20)),
                              border: Border.all(
                                color: isSel
                                    ? _engAccent.withAlpha(128)
                                    : (isDark
                                        ? Brand.darkBorder
                                        : Brand.borderLight),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSel) ...[
                                  const Icon(Icons.check_rounded,
                                      color: _engAccent, size: 12),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSel
                                        ? _engAccent
                                        : (isDark
                                            ? Brand.darkTextSecondary
                                            : Brand.subtleLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Bio', Icons.person_pin_rounded, isDark),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        border: Border.all(
                          color: isDark
                              ? Brand.darkBorder
                              : Brand.borderLight,
                        ),
                      ),
                      child: TextField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Short bio...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontSize: 13,
                          ),
                          enabledBorder: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            borderSide: BorderSide(
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue,
                                width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(24, 12, 24, viewInsets + 16),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              border: Border(
                top: BorderSide(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                ),
              ),
            ),
            child: GestureDetector(
              onTap: _isSaving ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: _isSaving
                      ? null
                      : const LinearGradient(
                          colors: [Brand.royalBlueDark, Brand.royalBlueLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: _isSaving
                      ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                      : null,
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  boxShadow: isDark || _isSaving
                      ? null
                      : [
                          BoxShadow(
                            color: Brand.royalBlue.withAlpha(89),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

