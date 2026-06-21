// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_installation_page.dart
// EA Machine Installations — Engineering Admin views + assigns engineers
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import 'ea_installation_detail_page.dart';

const Color _eaAccent = Brand.lightGreenDark;

// ── Type meta ──────────────────────────────────────────────────
const _typeLabels = {
  'new_install':    'New Install',
  'replacement':    'Replacement',
  'upgrade':        'Upgrade',
  'commissioning':  'Commissioning',
  'decommission':   'Decommission',
};
const _typeColors = {
  'new_install':    StatusColors.resolved,
  'replacement':    StatusColors.assigned,
  'upgrade':        AdminColors.info,
  'commissioning':  AdminColors.warning,
  'decommission':   AdminColors.error,
};

// ── Status meta ────────────────────────────────────────────────
const _statusLabels = {
  'pending':     'Pending',
  'scheduled':   'Scheduled',
  'in_progress': 'In Progress',
  'completed':   'Completed',
  'cancelled':   'Cancelled',
};
const _statusColors = {
  'pending':     AdminColors.warning,
  'scheduled':   AdminColors.info,
  'in_progress': StatusColors.assigned,
  'completed':   StatusColors.resolved,
  'cancelled':   StatusColors.gray,
};

class EaInstallationPage extends StatefulWidget {
  const EaInstallationPage({super.key});

  @override
  State<EaInstallationPage> createState() => _EaInstallationPageState();
}

class _EaInstallationPageState extends State<EaInstallationPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  String _statusFilter = 'all';
  String _search = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  static const _statusTabs = [
    'all', 'pending', 'scheduled', 'in_progress', 'completed', 'cancelled',
  ];

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

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await SupabaseConfig.client
          .from('machine_installations')
          .select('''
            id, title, installation_type, status,
            scheduled_date, location, created_at,
            customer:users!customer_id(id, full_name),
            machine:customer_machines!customer_machine_id(
              id, serial_number,
              catalog:machine_catalog!catalog_machine_id(machine_name, model_number)
            ),
            installation_engineers(id, status)
          ''')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(rows);
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilters() {
    var list = _all.where((r) {
      if (_statusFilter != 'all' && r['status'] != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final title = (r['title'] ?? '').toString().toLowerCase();
        final customer = ((r['customer'] as Map?)?['full_name'] ?? '').toString().toLowerCase();
        final machine  = ((r['machine'] as Map?)?['catalog'] as Map?)?['machine_name']?.toString().toLowerCase() ?? '';
        if (!title.contains(q) && !customer.contains(q) && !machine.contains(q)) return false;
      }
      return true;
    }).toList();
    _filtered = list;
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() { _search = v; _applyFilters(); });
    });
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: Column(
        children: [
          DsPageHeader(
            accent: HeroAccent.emerald,
            title: "Machine Installations",
            actions: [
              DsHeroAction(
                _searchOpen ? Icons.close : Icons.search,
                () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _searchCtrl.clear();
                      _search = "";
                      _applyFilters();
                    }
                  });
                },
                active: _searchOpen,
              ),
              const SizedBox(width: 6),
              DsHeroAction(Icons.refresh_rounded, _load),
            ],
            bottom: _searchOpen
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    cursorColor: Brand.emeraldBright,
                    decoration: const InputDecoration(
                      hintText: "Search installations…",
                      hintStyle: TextStyle(color: StatusColors.resolved, fontSize: 13),
                      isDense: true,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Brand.lightGreenDark),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Brand.emeraldBright),
                      ),
                    ),
                    onChanged: _onSearch,
                  )
                : null,
          ),
          // Status filter chips
          _buildStatusChips(isDark),
          // Content
          Expanded(child: _buildBody(isDark)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ea_install_fab',
        onPressed: _showCreateInstallationSheet,
        backgroundColor: _eaAccent,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Installation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Create Installation bottom sheet ─────────────────────────
  Future<void> _showCreateInstallationSheet() async {
    List<Map<String, dynamic>> machines = [];
    try {
      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('''
            id, serial_number,
            customer:users!user_id(id, full_name),
            catalog:machine_catalog!catalog_machine_id(machine_name, model_number)
          ''')
          .order('created_at', ascending: false)
          .limit(300);
      machines = List<Map<String, dynamic>>.from(data as List);
    } catch (_) {}

    if (!mounted) return;

    String? selMachineId;
    String? selCustomerId;
    String typeVal = 'new_install';
    DateTime? scheduledDate;
    String machSearch = '';

    final titleCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final machSearchCtrl = TextEditingController();

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSt) {
          final filtered = machines.where((m) {
            if (machSearch.isEmpty) return true;
            final q = machSearch.toLowerCase();
            final cat = m['catalog'] as Map? ?? {};
            final cust = m['customer'] as Map? ?? {};
            return (cat['machine_name'] as String? ?? '').toLowerCase().contains(q) ||
                (cust['full_name'] as String? ?? '').toLowerCase().contains(q) ||
                (m['serial_number'] as String? ?? '').toLowerCase().contains(q);
          }).take(8).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.92,
            maxChildSize: 0.97,
            minChildSize: 0.5,
            builder: (_, ctrl) => Container(
              decoration: BoxDecoration(
                color: AdminColors.card(sheetCtx),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(80),
                      borderRadius: BorderRadius.circular(Brand.r(2)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                    child: Row(
                      children: [
                        Icon(Icons.build_circle_rounded, color: _eaAccent, size: 22),
                        const SizedBox(width: 8),
                        Text('New Installation',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AdminColors.text(sheetCtx))),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        _sLabel('Select Machine *', sheetCtx),
                        const SizedBox(height: 8),
                        _sField(
                          context: sheetCtx,
                          child: TextField(
                            controller: machSearchCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Search machine / customer...',
                              prefixIcon: Icon(Icons.search, size: 18),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (v) => setSt(() => machSearch = v),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('No machines match.',
                                style: TextStyle(
                                    color: AdminColors.textHint(sheetCtx))),
                          ),
                        ...filtered.map((m) {
                          final cat = m['catalog'] as Map? ?? {};
                          final cust = m['customer'] as Map? ?? {};
                          final selected = selMachineId == m['id'];
                          return GestureDetector(
                            onTap: () => setSt(() {
                              selMachineId = m['id'] as String?;
                              selCustomerId = cust['id'] as String?;
                              if (titleCtrl.text.isEmpty) {
                                titleCtrl.text =
                                    'Install ${cat['machine_name'] ?? ''} – ${cust['full_name'] ?? ''}';
                              }
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _eaAccent.withAlpha(26)
                                    : AdminColors.bg(sheetCtx),
                                borderRadius: BorderRadius.circular(Brand.r(10)),
                                border: Border.all(
                                  color: selected
                                      ? _eaAccent
                                      : AdminColors.border(sheetCtx),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${cat['machine_name'] ?? ''} (${cat['model_number'] ?? ''})',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        '${cust['full_name'] ?? ''} • SN: ${m['serial_number'] ?? '—'}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AdminColors.textSub(sheetCtx)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle,
                                      color: _eaAccent, size: 18),
                              ]),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        _sLabel('Title *', sheetCtx),
                        const SizedBox(height: 6),
                        _sField(
                          context: sheetCtx,
                          child: TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Installation job title',
                                border: InputBorder.none,
                                isDense: true),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sLabel('Installation Type', sheetCtx),
                        const SizedBox(height: 6),
                        _sField(
                          context: sheetCtx,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: typeVal,
                              isExpanded: true,
                              isDense: true,
                              items: _typeLabels.entries
                                  .map((e) => DropdownMenuItem(
                                      value: e.key, child: Text(e.value)))
                                  .toList(),
                              onChanged: (v) => setSt(() => typeVal = v!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sLabel('Scheduled Date', sheetCtx),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: sheetCtx,
                              initialDate: scheduledDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 730)),
                            );
                            if (d != null) setSt(() => scheduledDate = d);
                          },
                          child: _sField(
                            context: sheetCtx,
                            child: Row(children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: AdminColors.textSub(sheetCtx)),
                              const SizedBox(width: 8),
                              Text(
                                scheduledDate != null
                                    ? DateFormat('dd MMM yyyy').format(scheduledDate!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: scheduledDate != null
                                      ? AdminColors.text(sheetCtx)
                                      : AdminColors.textHint(sheetCtx),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sLabel('Location', sheetCtx),
                        const SizedBox(height: 6),
                        _sField(
                          context: sheetCtx,
                          child: TextField(
                            controller: locCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Site address or location',
                                border: InputBorder.none,
                                isDense: true),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sLabel('Admin Notes', sheetCtx),
                        const SizedBox(height: 6),
                        _sField(
                          context: sheetCtx,
                          child: TextField(
                            controller: notesCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                hintText: 'Special instructions...',
                                border: InputBorder.none,
                                isDense: true),
                          ),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _eaAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(Brand.r(12))),
                          ),
                          onPressed: () async {
                            if (selMachineId == null) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(
                                      content: Text('Please select a machine')));
                              return;
                            }
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(
                                      content: Text('Please enter a title')));
                              return;
                            }
                            try {
                              final row = await SupabaseConfig.client
                                  .from('machine_installations')
                                  .insert({
                                    'customer_machine_id': selMachineId,
                                    'customer_id': selCustomerId,
                                    'title': title,
                                    'installation_type': typeVal,
                                    'scheduled_date': scheduledDate
                                        ?.toIso8601String()
                                        .split('T')[0],
                                    'location': locCtrl.text.trim().isEmpty
                                        ? null
                                        : locCtrl.text.trim(),
                                    'admin_notes': notesCtrl.text.trim().isEmpty
                                        ? null
                                        : notesCtrl.text.trim(),
                                    'created_by':
                                        SupabaseConfig.client.auth.currentUser?.id,
                                  })
                                  .select()
                                  .single();
                              if (!sheetCtx.mounted) return;
                              Navigator.pop(sheetCtx, true);
                              if (mounted) {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EaInstallationDetailPage(
                                        installationId: row['id'] as String),
                                  ),
                                );
                                if (changed == true) _load();
                                _load();
                              }
                            } catch (e) {
                              if (!sheetCtx.mounted) return;
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: StatusColors.danger,
                              ));
                            }
                          },
                          child: const Text('Create Installation',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
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

  // ── Small sheet helpers (private to this file) ─────────────────
  Widget _sLabel(String t, BuildContext c) => Text(t,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AdminColors.text(c)));

  Widget _sField({required Widget child, required BuildContext context}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AdminColors.bg(context),
          borderRadius: BorderRadius.circular(Brand.r(10)),
          border: Border.all(color: AdminColors.border(context)),
        ),
        child: child,
      );

  Widget _buildStatusChips(bool isDark) {
    return Container(
      height: 48,
      color: isDark ? Brand.darkCard : Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _statusTabs.length,
        itemBuilder: (_, i) {
          final s = _statusTabs[i];
          final active = _statusFilter == s;
          final label = s == 'all' ? 'All' : (_statusLabels[s] ?? s);
          final count = s == 'all'
              ? _all.length
              : _all.where((r) => r['status'] == s).length;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('$label ($count)'),
              selected: active,
              onSelected: (_) {
                setState(() { _statusFilter = s; _applyFilters(); });
              },
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
        },
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) return _buildShimmer(isDark);
    if (_error != null) return _buildError();
    if (_filtered.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      color: _eaAccent,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _InstallCard(
          data: _filtered[i],
          onTap: () => _openDetail(_filtered[i]['id'] as String),
        ),
      ),
    );
  }

  Future<void> _openDetail(String id) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EaInstallationDetailPage(installationId: id),
      ),
    );
    if (changed == true) _load();
  }

  // ── Error / empty / shimmer ───────────────────────────────────

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AdminColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: AdminColors.textSub(context))),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_circle_outlined,
                size: 56, color: AdminColors.textHint(context)),
            const SizedBox(height: 12),
            Text('No installations found',
                style: TextStyle(
                    fontSize: 16, color: AdminColors.textSub(context))),
          ],
        ),
      );

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 100,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(Brand.r(16)),
          ),
        );
      },
    );
  }
}

// ── Installation card ─────────────────────────────────────────

class _InstallCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _InstallCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['status'] as String? ?? 'pending';
    final type   = data['installation_type'] as String? ?? 'new_install';
    final statusColor = _statusColors[status] ?? StatusColors.gray;
    final typeColor   = _typeColors[type] ?? StatusColors.gray;

    final customer = (data['customer'] as Map?)?['full_name'] ?? '—';
    final machineMap = data['machine'] as Map?;
    final catalogMap = machineMap?['catalog'] as Map?;
    final machineName = catalogMap?['machine_name'] ?? '—';
    final serialNo = machineMap?['serial_number'] ?? '';

    final engineers = data['installation_engineers'] as List? ?? [];
    final activeEng = engineers
        .where((e) => (e['status'] as String?) != 'removed')
        .length;

    final scheduled = data['scheduled_date'] as String?;
    final location = data['location'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: type badge + status badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Text(
                      _typeLabels[type] ?? type,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: typeColor),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Text(
                      _statusLabels[status] ?? status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                data['title'] ?? 'Untitled',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.text(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Machine + customer
              Text(
                '$machineName${serialNo.isNotEmpty ? ' · $serialNo' : ''} — $customer',
                style: TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSub(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Row 3: engineers + date/location
              Row(
                children: [
                  Icon(Icons.engineering_rounded,
                      size: 14, color: _eaAccent),
                  const SizedBox(width: 4),
                  Text('$activeEng engineer${activeEng == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12, color: AdminColors.textSub(context))),
                  if (scheduled != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: AdminColors.textHint(context)),
                    const SizedBox(width: 4),
                    Text(scheduled,
                        style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSub(context))),
                  ],
                  if (location != null && location.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.location_on_outlined,
                        size: 13, color: AdminColors.textHint(context)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(location,
                          style: TextStyle(
                              fontSize: 12,
                              color: AdminColors.textSub(context)),
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
    );
  }
}
