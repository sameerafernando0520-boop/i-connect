// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineer/engineer_installation_list_page.dart
// Engineer — My Machine Installations (assigned to me)
// Ticket-like status tabs: assigned → acknowledged → in_progress → completed
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import 'engineer_installation_detail_page.dart';

const Color _engAccent = Color(0xFF00B4D8);

const _instTypeLabels = {
  'new_install':   'New Install',
  'replacement':   'Replacement',
  'upgrade':       'Upgrade',
  'commissioning': 'Commissioning',
  'decommission':  'Decommission',
};
const _instTypeColors = {
  'new_install':   Color(0xFF10B981),
  'replacement':   Color(0xFF8B5CF6),
  'upgrade':       Color(0xFF3B82F6),
  'commissioning': Color(0xFFF59E0B),
  'decommission':  Color(0xFFEF4444),
};
const _instStatusLabels = {
  'pending':     'Pending',
  'scheduled':   'Scheduled',
  'in_progress': 'In Progress',
  'completed':   'Completed',
  'cancelled':   'Cancelled',
};
const _instStatusColors = {
  'pending':     Color(0xFFF59E0B),
  'scheduled':   Color(0xFF3B82F6),
  'in_progress': Color(0xFF8B5CF6),
  'completed':   Color(0xFF10B981),
  'cancelled':   Color(0xFF6B7280),
};
// Engineer's own status on this installation
const _myStatusColors = {
  'assigned':     Color(0xFFF59E0B),
  'acknowledged': Color(0xFF3B82F6),
  'in_progress':  Color(0xFF8B5CF6),
  'completed':    Color(0xFF10B981),
};

class EngineerInstallationListPage extends StatefulWidget {
  const EngineerInstallationListPage({super.key});

  @override
  State<EngineerInstallationListPage> createState() =>
      _EngineerInstallationListPageState();
}

class _EngineerInstallationListPageState
    extends State<EngineerInstallationListPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  String _statusFilter = 'all';

  static const _tabs = [
    'all', 'assigned', 'in_progress', 'completed',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      // 1. Get my installation assignments
      final engRows = await SupabaseConfig.client
          .from('installation_engineers')
          .select('''
            id, role, status, assigned_at, acknowledged_at,
            installation:machine_installations!installation_id(
              id, title, installation_type, status, scheduled_date,
              location, created_at,
              customer:users!customer_id(id, full_name),
              machine:customer_machines!customer_machine_id(
                id, serial_number,
                catalog:machine_catalog!catalog_machine_id(machine_name, model_number)
              )
            )
          ''')
          .eq('engineer_id', uid)
          .neq('status', 'removed')
          .order('assigned_at', ascending: false);

      if (!mounted) return;

      // Flatten: merge my eng status into the installation row
      final items = (engRows as List).map((e) {
        final inst = Map<String, dynamic>.from(
            (e['installation'] as Map<String, dynamic>?) ?? {});
        inst['_my_role']   = e['role'];
        inst['_my_status'] = e['status'];
        inst['_eng_id']    = e['id'];
        return inst;
      }).toList();

      setState(() {
        _all = items;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilter() {
    if (_statusFilter == 'all') {
      _filtered = List.from(_all);
    } else {
      // Filter by installation status grouping:
      // 'assigned' tab → inst status pending/scheduled + my status = assigned/acknowledged
      // 'in_progress' tab → inst status in_progress
      // 'completed' tab → inst status completed
      if (_statusFilter == 'assigned') {
        _filtered = _all.where((r) {
          final s = r['status'] as String? ?? '';
          return s == 'pending' || s == 'scheduled';
        }).toList();
      } else {
        _filtered = _all
            .where((r) => (r['status'] as String?) == _statusFilter)
            .toList();
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        elevation: 0,
        title: const Text(
          'My Installations',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildTabs(bool isDark) {
    return Container(
      height: 48,
      color: isDark ? Brand.darkCard : Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _tabs.length,
        itemBuilder: (_, i) {
          final s = _tabs[i];
          final active = _statusFilter == s;
          final label = s == 'all'
              ? 'All'
              : s == 'assigned'
                  ? 'Upcoming'
                  : s == 'in_progress'
                      ? 'In Progress'
                      : 'Completed';
          final count = s == 'all'
              ? _all.length
              : s == 'assigned'
                  ? _all
                      .where((r) =>
                          (r['status'] as String?) == 'pending' ||
                          (r['status'] as String?) == 'scheduled')
                      .length
                  : _all
                      .where((r) => (r['status'] as String?) == s)
                      .length;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('$label ($count)'),
              selected: active,
              onSelected: (_) {
                setState(() { _statusFilter = s; _applyFilter(); });
              },
              selectedColor: _engAccent.withAlpha(30),
              checkmarkColor: _engAccent,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? _engAccent : Colors.grey,
              ),
              side: BorderSide(
                color: active ? _engAccent : Colors.grey.withAlpha(80),
              ),
              backgroundColor: isDark ? Brand.darkCardElevated : Colors.white,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) return _buildShimmer(isDark);
    if (_error != null) return _buildError(isDark);
    if (_filtered.isEmpty) return _buildEmpty(isDark);

    return RefreshIndicator(
      color: _engAccent,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: _filtered.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${_filtered.length} installation${_filtered.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EngInstallCard(
              data: _filtered[i - 1],
              onTap: () => _openDetail(_filtered[i - 1]['id'] as String),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDetail(String id) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EngineerInstallationDetailPage(installationId: id),
      ),
    );
    if (changed == true) _load();
  }

  Widget _buildError(bool isDark) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withAlpha(isDark ? 25 : 15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  color: Color(0xFFEF4444), size: 36),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const SizedBox(height: 6),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                )),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: _engAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ]),
        ),
      );

  Widget _buildEmpty(bool isDark) => RefreshIndicator(
        color: _engAccent,
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _engAccent.withAlpha(isDark ? 25 : 20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.precision_manufacturing_outlined,
                        size: 40, color: isDark ? _engAccent : const Color(0xFF0096B7)),
                  ),
                  const SizedBox(height: 16),
                  Text('No installations found',
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600,
                        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    _statusFilter == 'all'
                        ? 'No installations assigned to you yet'
                        : 'No installations in this category',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 110,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

// ── Engineer installation card ─────────────────────────────────

class _EngInstallCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _EngInstallCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status   = data['status'] as String? ?? 'pending';
    final type     = data['installation_type'] as String? ?? 'new_install';
    final myStatus = data['_my_status'] as String? ?? 'assigned';
    final myRole   = data['_my_role'] as String? ?? 'technician';

    final statusColor = _instStatusColors[status] ?? const Color(0xFF6B7280);
    final typeColor   = _instTypeColors[type] ?? const Color(0xFF6B7280);
    final myStatusColor = _myStatusColors[myStatus] ?? const Color(0xFF6B7280);

    final customer = (data['customer'] as Map?)?['full_name'] ?? '—';
    final machineMap = data['machine'] as Map?;
    final catalogMap = machineMap?['catalog'] as Map?;
    final machineName = catalogMap?['machine_name'] ?? '—';
    final serialNo    = machineMap?['serial_number'] ?? '';

    final scheduled = data['scheduled_date'] as String?;
    final location  = data['location'] as String?;

    // Role label
    final roleLabel = myRole == 'lead'
        ? 'Lead'
        : myRole == 'assistant'
            ? 'Assistant'
            : 'Technician';

    // My status label
    final myStatusLabel = myStatus == 'assigned'
        ? 'Assigned'
        : myStatus == 'acknowledged'
            ? 'Acknowledged'
            : myStatus == 'in_progress'
                ? 'In Progress'
                : myStatus == 'completed'
                    ? 'Completed'
                    : myStatus;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Color sidebar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Row 1: Badges ──
                      Row(
                        children: [
                          _badge(_instTypeLabels[type] ?? type, typeColor, isDark),
                          const SizedBox(width: 6),
                          _badge(roleLabel, _engAccent, isDark),
                          const Spacer(),
                          _badge(_instStatusLabels[status] ?? status,
                              statusColor, isDark),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Title ──
                      Text(
                        data['title'] ?? 'Untitled',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // ── Machine + Customer ──
                      Row(
                        children: [
                          Icon(Icons.precision_manufacturing_outlined,
                              size: 14,
                              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$machineName${serialNo.isNotEmpty ? ' · S/N: $serialNo' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 14,
                              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                          const SizedBox(width: 6),
                          Text(customer,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                              )),
                        ],
                      ),

                      // ── Bottom Row: my status + date + location ──
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // My status pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: myStatusColor.withAlpha(isDark ? 30 : 18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: myStatusColor.withAlpha(60)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    color: myStatusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(myStatusLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: myStatusColor,
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (scheduled != null) ...[
                            Icon(Icons.calendar_today_outlined,
                                size: 12,
                                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                            const SizedBox(width: 4),
                            Text(scheduled,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                                )),
                          ],
                          if (location != null && location.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.location_on_outlined,
                                size: 12,
                                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(location,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Chevron ──
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right,
                    size: 20,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
