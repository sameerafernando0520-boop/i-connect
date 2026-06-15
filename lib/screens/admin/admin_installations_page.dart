// lib/screens/admin/admin_installations_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import 'admin_installation_detail_page.dart';

const _typeLabels = {
  'new_install':   'New Install',
  'replacement':   'Replacement',
  'upgrade':       'Upgrade',
  'commissioning': 'Commissioning',
  'decommission':  'Decommission',
};

const _typeColors = {
  'new_install':   Color(0xFF10B981),
  'replacement':   Color(0xFF3B82F6),
  'upgrade':       Color(0xFF8B5CF6),
  'commissioning': Color(0xFFF59E0B),
  'decommission':  Color(0xFFEF4444),
};

const _statusColors = {
  'pending':     Color(0xFFF59E0B),
  'scheduled':   Color(0xFF3B82F6),
  'in_progress': Color(0xFF8B5CF6),
  'completed':   Color(0xFF10B981),
  'cancelled':   Color(0xFF6B7280),
};

// ══════════════════════════════════════════════════════════════
//  ADMIN INSTALLATIONS PAGE
// ══════════════════════════════════════════════════════════════
class AdminInstallationsPage extends StatefulWidget {
  const AdminInstallationsPage({super.key});

  @override
  State<AdminInstallationsPage> createState() =>
      _AdminInstallationsPageState();
}

class _AdminInstallationsPageState extends State<AdminInstallationsPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  String _statusFilter = 'all';
  String _searchQuery = '';
  bool _showSearch = false;
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

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await SupabaseConfig.client
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
        _all = List<Map<String, dynamic>>.from(data as List);
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final list = _all.where((item) {
      final status = item['status'] as String? ?? '';
      final matchStatus =
          _statusFilter == 'all' || status == _statusFilter;
      if (_searchQuery.isEmpty) return matchStatus;
      final q = _searchQuery.toLowerCase();
      final title =
          (item['title'] as String? ?? '').toLowerCase();
      final customer =
          ((item['customer'] as Map?)?['full_name'] as String? ?? '')
              .toLowerCase();
      final loc =
          (item['location'] as String? ?? '').toLowerCase();
      return matchStatus &&
          (title.contains(q) ||
              customer.contains(q) ||
              loc.contains(q));
    }).toList();
    setState(() => _filtered = list);
  }

  // ── Create installation bottom sheet ─────────────────────────
  Future<void> _showCreateSheet() async {
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

    final result = await showModalBottomSheet<bool>(
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
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  _SheetHandle(context: sheetCtx),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                    child: Row(
                      children: [
                        Text('New Installation',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AdminColors.text(sheetCtx))),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetCtx, false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // Machine picker
                        _Label('Select Machine *', sheetCtx),
                        const SizedBox(height: 8),
                        _Field(
                          context: sheetCtx,
                          child: TextField(
                            controller: machSearchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search machine / customer...',
                              prefixIcon:
                                  const Icon(Icons.search, size: 18),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                setSt(() => machSearch = v),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...filtered.map((m) {
                          final cat = m['catalog'] as Map? ?? {};
                          final cust = m['customer'] as Map? ?? {};
                          final selected = selMachineId == m['id'];
                          return GestureDetector(
                            onTap: () => setSt(() {
                              selMachineId = m['id'] as String?;
                              selCustomerId =
                                  cust['id'] as String?;
                              if (titleCtrl.text.isEmpty) {
                                titleCtrl.text =
                                    'Install ${cat['machine_name'] ?? ''} – ${cust['full_name'] ?? ''}';
                              }
                            }),
                            child: Container(
                              margin:
                                  const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AdminColors.primary
                                        .withAlpha(26)
                                    : AdminColors.bg(sheetCtx),
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AdminColors.primary
                                      : AdminColors.border(
                                          sheetCtx),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${cat['machine_name'] ?? ''} (${cat['model_number'] ?? ''})',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600,
                                              fontSize: 13),
                                        ),
                                        Text(
                                          '${cust['full_name'] ?? ''} • SN: ${m['serial_number'] ?? '—'}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AdminColors
                                                  .textSub(
                                                      sheetCtx)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle,
                                        color: AdminColors.primary,
                                        size: 18),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        // Title
                        _Label('Title *', sheetCtx),
                        const SizedBox(height: 6),
                        _Field(
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
                        // Type
                        _Label('Installation Type', sheetCtx),
                        const SizedBox(height: 6),
                        _Field(
                          context: sheetCtx,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: typeVal,
                              isExpanded: true,
                              isDense: true,
                              items: _typeLabels.entries
                                  .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value)))
                                  .toList(),
                              onChanged: (v) =>
                                  setSt(() => typeVal = v!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Scheduled date
                        _Label('Scheduled Date', sheetCtx),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: sheetCtx,
                              initialDate:
                                  scheduledDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 730)),
                            );
                            if (d != null) {
                              setSt(() => scheduledDate = d);
                            }
                          },
                          child: _Field(
                            context: sheetCtx,
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 16,
                                    color: AdminColors.textSub(
                                        sheetCtx)),
                                const SizedBox(width: 8),
                                Text(
                                  scheduledDate != null
                                      ? DateFormat('dd MMM yyyy')
                                          .format(scheduledDate!)
                                      : 'Select date',
                                  style: TextStyle(
                                    color: scheduledDate != null
                                        ? AdminColors.text(sheetCtx)
                                        : AdminColors.textHint(
                                            sheetCtx),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Location
                        _Label('Location', sheetCtx),
                        const SizedBox(height: 6),
                        _Field(
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
                        // Notes
                        _Label('Admin Notes', sheetCtx),
                        const SizedBox(height: 6),
                        _Field(
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
                            backgroundColor: AdminColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            if (selMachineId == null) {
                              ScaffoldMessenger.of(sheetCtx)
                                  .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Please select a machine')));
                              return;
                            }
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(sheetCtx)
                                  .showSnackBar(const SnackBar(
                                      content:
                                          Text('Please enter a title')));
                              return;
                            }
                            try {
                              final row = await SupabaseConfig.client
                                  .from('machine_installations')
                                  .insert({
                                    'customer_machine_id':
                                        selMachineId,
                                    'customer_id': selCustomerId,
                                    'title': title,
                                    'installation_type': typeVal,
                                    'scheduled_date': scheduledDate
                                        ?.toIso8601String()
                                        .split('T')[0],
                                    'location': locCtrl.text.trim().isEmpty
                                        ? null
                                        : locCtrl.text.trim(),
                                    'admin_notes': notesCtrl.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : notesCtrl.text.trim(),
                                    'created_by': SupabaseConfig
                                        .client.auth.currentUser?.id,
                                  })
                                  .select()
                                  .single();
                              if (!sheetCtx.mounted) return;
                              Navigator.pop(sheetCtx, true);
                              if (mounted) {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AdminInstallationDetailPage(
                                            installationId:
                                                row['id'] as String),
                                  ),
                                );
                                if (changed == true) _load();
                              }
                            } catch (e) {
                              if (!sheetCtx.mounted) return;
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AdminColors.error),
                              );
                            }
                          },
                          child: const Text('Create Installation',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
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

    titleCtrl.dispose();
    locCtrl.dispose();
    notesCtrl.dispose();
    machSearchCtrl.dispose();

    if (result == true) _load();
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: 'Installations',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _applyFilter();
                }
              });
            },
          ),
        ],
        bottom: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search installations...',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(153)),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _applyFilter();
                },
              )
            : null,
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              children: [
                for (final s in [
                  'all',
                  'pending',
                  'scheduled',
                  'in_progress',
                  'completed',
                  'cancelled'
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_statusLabel(s),
                          style: const TextStyle(fontSize: 12)),
                      selected: _statusFilter == s,
                      selectedColor: s == 'all'
                          ? AdminColors.primary
                          : (_statusColors[s] ??
                              AdminColors.primary),
                      labelStyle: TextStyle(
                        color: _statusFilter == s
                            ? Colors.white
                            : AdminColors.text(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      backgroundColor: AdminColors.card(context),
                      onSelected: (_) {
                        setState(() => _statusFilter = s);
                        _applyFilter();
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 100),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) =>
                                  _InstallationCard(
                                data: _filtered[i],
                                onTap: () async {
                                  final changed =
                                      await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AdminInstallationDetailPage(
                                        installationId: _filtered[i]
                                            ['id'] as String,
                                      ),
                                    ),
                                  );
                                  if (changed == true) _load();
                                },
                              ),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AdminColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Installation',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: AdminColors.error),
              const SizedBox(height: 12),
              Text('Failed to load',
                  style: TextStyle(
                      color: AdminColors.text(context),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(
                      color: AdminColors.textSub(context),
                      fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _load,
                  child: const Text('Retry')),
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
            Text(
              _statusFilter == 'all'
                  ? 'No installations yet'
                  : 'No $_statusFilter installations',
              style: TextStyle(
                  color: AdminColors.text(context),
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Tap + to create one',
                style: TextStyle(
                    color: AdminColors.textSub(context),
                    fontSize: 12)),
          ],
        ),
      );

  String _statusLabel(String s) => switch (s) {
        'all' => 'All',
        'pending' => 'Pending',
        'scheduled' => 'Scheduled',
        'in_progress' => 'In Progress',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };
}

// ── Shared helpers ─────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  final BuildContext context;
  const _SheetHandle({required this.context});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
            color: AdminColors.border(context),
            borderRadius: BorderRadius.circular(2)),
      );
}

class _Label extends StatelessWidget {
  final String text;
  final BuildContext ctx;
  const _Label(this.text, this.ctx);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AdminColors.textSub(ctx)));
}

class _Field extends StatelessWidget {
  final Widget child;
  final BuildContext context;
  const _Field({required this.child, required this.context});
  @override
  Widget build(BuildContext ctx) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AdminColors.bg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.border(context)),
        ),
        child: child,
      );
}

// ── Installation Card ─────────────────────────────────────────
class _InstallationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _InstallationCard(
      {required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['status'] as String? ?? 'pending';
    final type =
        data['installation_type'] as String? ?? 'new_install';
    final customer = data['customer'] as Map? ?? {};
    final machine = data['machine'] as Map? ?? {};
    final catalog = machine['catalog'] as Map? ?? {};
    final engineers =
        (data['installation_engineers'] as List?) ?? [];
    final active =
        engineers.where((e) => e['status'] != 'removed').length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AdminColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border(context)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(
                      _typeLabels[type] ?? type,
                      _typeColors[type] ?? Colors.grey),
                  const SizedBox(width: 8),
                  _badge(
                      _fmtStatus(status),
                      _statusColors[status] ?? Colors.grey),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      color: AdminColors.textHint(context),
                      size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data['title'] as String? ?? '(Untitled)',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 13,
                      color: AdminColors.textSub(context)),
                  const SizedBox(width: 4),
                  Text(
                      customer['full_name'] as String? ?? '—',
                      style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context))),
                  const SizedBox(width: 12),
                  Icon(Icons.precision_manufacturing_outlined,
                      size: 13,
                      color: AdminColors.textSub(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        catalog['machine_name'] as String? ?? '—',
                        style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSub(context)),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (data['scheduled_date'] != null) ...[
                    Icon(Icons.calendar_today,
                        size: 13,
                        color: AdminColors.textSub(context)),
                    const SizedBox(width: 4),
                    Text(
                        _fmtDate(
                            data['scheduled_date'] as String?),
                        style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSub(context))),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.engineering,
                      size: 13,
                      color: AdminColors.textSub(context)),
                  const SizedBox(width: 4),
                  Text(
                      '$active engineer${active == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  String _fmtDate(String? s) {
    if (s == null) return '—';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  String _fmtStatus(String s) => switch (s) {
        'in_progress' => 'In Progress',
        'pending' => 'Pending',
        'scheduled' => 'Scheduled',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };
}
