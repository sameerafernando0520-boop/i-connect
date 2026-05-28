// lib/screens/admin/machines_management_page.dart
// Fixed: AdminColors.textPrimary removed, Colors.red/orange/blue → AdminColors,
//   _isDark anti-pattern fixed, mounted guards, sheetCtx, border radius 28,
//   _isRefreshing setState, duplicate mounted check removed

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';

// ══════════════════════════════════════════════════════════════
//  MACHINES MANAGEMENT PAGE
// ══════════════════════════════════════════════════════════════
class MachinesManagementPage extends StatefulWidget {
  const MachinesManagementPage({super.key});

  @override
  State<MachinesManagementPage> createState() => _MachinesManagementPageState();
}

class _MachinesManagementPageState extends State<MachinesManagementPage> {
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _filteredMachines = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _filterCategory = 'all';
  String _filterStatus = 'all';
  String _sortBy = 'default';
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  // ── Theme helpers (getters using Theme.of(context)) ──
  // ⚠️ NOT stored as fields — computed per access in build tree
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _scaffoldBg => _isDark ? Brand.darkBg : Brand.scaffoldLight;
  Color get _cardBg => _isDark ? Brand.darkCard : Colors.white;
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
  Color get _textSecondary =>
      _isDark ? Brand.darkTextSecondary : Colors.grey.shade600;
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : Colors.grey.shade400;
  Color get _borderColor => _isDark ? Brand.darkBorder : Colors.grey.shade200;
  Color get _dividerColor =>
      _isDark ? Brand.darkBorderLight : Colors.grey.shade200;
  Color get _chipBg => _isDark ? Brand.darkCardElevated : Colors.white;
  Color get _sheetBg => _isDark ? Brand.darkCard : Colors.white;
  Color get _handleColor =>
      _isDark ? Brand.darkBorderLight : Colors.grey.shade300;
  Color get _primaryColor =>
      _isDark ? Brand.royalBlueGlow : AdminColors.primary;
  Color get _accentColor =>
      _isDark ? Brand.lightGreenBright : AdminColors.accent;
  Color get _elevatedFill =>
      _isDark ? const Color(0xFF22272E) : Colors.grey.shade100;

  List<BoxShadow> get _cardShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ];

  List<BoxShadow> get _softShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 200;
      if (show != _showScrollTop) {
        setState(() => _showScrollTop = show);
      }
    });
    _loadMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadMachines({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    } else {
      // ✅ setState required even for silent refresh flag
      setState(() => _isRefreshing = true);
    }

    try {
      List<Map<String, dynamic>> machines;
      try {
        final result =
            await SupabaseConfig.client.rpc('get_machines_with_stats');
        if (!mounted) return;
        machines = List<Map<String, dynamic>>.from(result as List);
      } catch (_) {
        final data = await SupabaseConfig.client
            .from('machine_catalog')
            .select('*')
            .order('display_order', ascending: true);
        if (!mounted) return;
        machines = List<Map<String, dynamic>>.from(data);
      }

      if (!mounted) return;
      setState(() {
        _machines = machines;
        _applyFilters();
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      _showSnackBar('Error loading machines: $e', isError: true);
    }
  }

  // ─── FILTERING & SORTING ───────────────────────────────────
  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_machines);

    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered = filtered.where((m) {
        return [
          m['machine_name'],
          m['model_number'],
          m['brand'],
          m['category'],
          m['sub_category'],
          m['description'],
        ].any((f) => f != null && f.toString().toLowerCase().contains(query));
      }).toList();
    }

    if (_filterCategory != 'all') {
      filtered =
          filtered.where((m) => m['category'] == _filterCategory).toList();
    }

    if (_filterStatus == 'active') {
      filtered = filtered.where((m) => m['is_active'] == true).toList();
    } else if (_filterStatus == 'inactive') {
      filtered = filtered.where((m) => m['is_active'] != true).toList();
    }

    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => (a['machine_name'] ?? '')
            .toString()
            .compareTo((b['machine_name'] ?? '').toString()));
        break;
      case 'newest':
        filtered.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        break;
      case 'oldest':
        filtered.sort(
            (a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));
        break;
      case 'inquiries':
        filtered.sort((a, b) => ((b['inquiry_count'] ?? 0) as num)
            .compareTo((a['inquiry_count'] ?? 0) as num));
        break;
      case 'owners':
        filtered.sort((a, b) => ((b['owners_count'] ?? 0) as num)
            .compareTo((a['owners_count'] ?? 0) as num));
        break;
      default:
        filtered.sort((a, b) => ((a['display_order'] ?? 999) as num)
            .compareTo((b['display_order'] ?? 999) as num));
    }

    _filteredMachines = filtered;
  }

  // ─── ACTIONS ───────────────────────────────────────────────
  Future<void> _toggleMachineStatus(Map<String, dynamic> machine) async {
    final newStatus = !(machine['is_active'] ?? true);
    final machineName = machine['machine_name'] ?? 'Machine';

    final confirmed = await _showConfirmSheet(
      icon: newStatus ? Icons.visibility_rounded : Icons.visibility_off_rounded,
      iconColor: newStatus ? _accentColor : AdminColors.error,
      title: newStatus ? 'Activate Machine?' : 'Deactivate Machine?',
      message: newStatus
          ? '"$machineName" will be visible to customers.'
          : '"$machineName" will be hidden from customers.',
      confirmLabel: newStatus ? 'Activate' : 'Deactivate',
      confirmColor: newStatus ? _accentColor : AdminColors.error,
    );
    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.from('machine_catalog').update({
        'is_active': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', machine['id'] as String);

      if (!mounted) return;
      _showSnackBar(
        newStatus ? 'Machine activated' : 'Machine deactivated',
        icon:
            newStatus ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        color: newStatus ? _accentColor : AdminColors.warning,
      );
      await _loadMachines(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error: $e', isError: true);
    }
  }

  Future<void> _deleteMachine(Map<String, dynamic> machine) async {
    final machineName = machine['machine_name'] ?? 'Machine';

    final confirmed = await _showConfirmSheet(
      icon: Icons.delete_forever_rounded,
      iconColor: AdminColors.error,
      title: 'Delete Machine?',
      message:
          'This will permanently remove "$machineName" from the catalog. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AdminColors.error,
      isDangerous: true,
    );
    if (confirmed != true) return;

    try {
      final result = await SupabaseConfig.client.rpc(
        'delete_machine_safe',
        params: {'p_machine_id': machine['id']},
      );
      if (!mounted) return;
      final res = result as Map<String, dynamic>;
      if (res['success'] == true) {
        _showSnackBar('Machine deleted', icon: Icons.delete_rounded);
        await _loadMachines(silent: true);
      } else {
        final owners = res['owners'] ?? 0;
        final tickets = res['tickets'] ?? 0;
        _showSnackBar(
          'Cannot delete: $owners owners, $tickets tickets linked. Deactivate instead.',
          isError: true,
          duration: 4,
        );
      }
    } catch (e) {
      if (!mounted) return;
      try {
        await SupabaseConfig.client
            .from('machine_catalog')
            .delete()
            .eq('id', machine['id'] as String);
        if (!mounted) return;
        _showSnackBar('Machine deleted');
        await _loadMachines(silent: true);
      } catch (e2) {
        if (!mounted) return;
        _showSnackBar('Cannot delete: $e2', isError: true);
      }
    }
  }

  Future<void> _duplicateMachine(Map<String, dynamic> machine) async {
    HapticFeedback.mediumImpact();
    try {
      final newId = await SupabaseConfig.client.rpc(
        'duplicate_machine',
        params: {'p_machine_id': machine['id']},
      );
      if (!mounted) return;
      _showSnackBar('Machine duplicated! Opening editor...',
          icon: Icons.copy_rounded);
      await _loadMachines(silent: true);
      if (!mounted) return;
      final newMachine = _machines.firstWhere(
        (m) => m['id'] == newId,
        orElse: () => {},
      );
      if (newMachine.isNotEmpty && mounted) {
        _editMachine(newMachine);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Duplicate failed: $e', isError: true);
    }
  }

  Future<void> _bulkToggle(bool activate) async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    final confirmed = await _showConfirmSheet(
      icon: activate ? Icons.visibility_rounded : Icons.visibility_off_rounded,
      iconColor: activate ? _accentColor : AdminColors.error,
      title: activate
          ? 'Activate $count machines?'
          : 'Deactivate $count machines?',
      message: activate
          ? 'All selected machines will be visible to customers.'
          : 'All selected machines will be hidden from customers.',
      confirmLabel: activate ? 'Activate All' : 'Deactivate All',
      confirmColor: activate ? _accentColor : AdminColors.error,
    );
    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.rpc('bulk_toggle_machines', params: {
        'p_machine_ids': _selectedIds.toList(),
        'p_is_active': activate,
      });
      if (!mounted) return;
      _showSnackBar(
        '$count machines ${activate ? 'activated' : 'deactivated'}',
        icon: Icons.check_circle_rounded,
        color: _accentColor,
      );
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      await _loadMachines(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Bulk update failed: $e', isError: true);
    }
  }

  void _editMachine(Map<String, dynamic>? machine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MachineEditorPage(machine: machine),
      ),
    ).then((_) => _loadMachines(silent: true));
  }

  void _viewMachineDetail(Map<String, dynamic> machine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MachineDetailSheet(machineId: machine['id'] as String),
      ),
    ).then((_) => _loadMachines(silent: true));
  }

  // ─── HELPERS ───────────────────────────────────────────────
  List<String> get _categories {
    final cats = _machines
        .map((m) => m['category']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    cats.sort();
    return cats;
  }

  int get _activeCount => _machines.where((m) => m['is_active'] == true).length;

  int get _inactiveCount =>
      _machines.where((m) => m['is_active'] != true).length;

  String _shortenCategory(String category) {
    switch (category) {
      case 'Digital Printers':
        return 'Printers';
      case 'CNC Routers':
        return 'CNC';
      case 'Laser Cutters':
        return 'Laser';
      case 'Finishing Equipment':
        return 'Finishing';
      default:
        return category.length > 10
            ? '${category.substring(0, 10)}…'
            : category;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Digital Printers':
        return Icons.print_rounded;
      case 'CNC Routers':
        return Icons.precision_manufacturing_rounded;
      case 'Laser Cutters':
        return Icons.flash_on_rounded;
      case 'Finishing Equipment':
        return Icons.layers_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Digital Printers':
        return const Color(0xFF262261);
      case 'CNC Routers':
        return const Color(0xFFABBD37);
      case 'Laser Cutters':
        return AdminColors.warning;
      case 'Finishing Equipment':
        return AdminColors.info;
      default:
        return Colors.grey;
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    IconData? icon,
    Color? color,
    int duration = 2,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ] else ...[
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : color ?? _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: duration),
      ),
    );
  }

  Future<bool?> _showConfirmSheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    bool isDangerous = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                // ✅ .withAlpha() not .withOpacity()
                color: iconColor.withAlpha(_isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: _borderColor),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: confirmColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      floatingActionButton: _isSelectionMode ? null : _buildFAB(),
      body: SafeArea(
        child: Column(
          children: [
            _isSelectionMode ? _buildSelectionHeader() : _buildTopHeader(),
            Expanded(
              child: _isLoading
                  ? _buildLoadingSkeleton()
                  : RefreshIndicator(
                      onRefresh: _loadMachines,
                      color: _accentColor,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildStatsRow()),
                          SliverToBoxAdapter(child: _buildSearchBar()),
                          SliverToBoxAdapter(child: _buildFilterChips()),
                          SliverToBoxAdapter(child: _buildResultsHeader()),
                          _filteredMachines.isEmpty
                              ? SliverFillRemaining(child: _buildEmptyState())
                              : SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 20, 100),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _buildMachineCard(
                                          _filteredMachines[index]),
                                      childCount: _filteredMachines.length,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SELECTION HEADER ──────────────────────────────────────
  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: _primaryColor,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _isSelectionMode = false;
              _selectedIds.clear();
            }),
            child:
                const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Text(
            '${_selectedIds.length} selected',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                if (_selectedIds.length == _filteredMachines.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds =
                      _filteredMachines.map((m) => m['id'].toString()).toSet();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedIds.length == _filteredMachines.length
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _selectedIds.isEmpty ? null : () => _bulkToggle(true),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentColor.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Icon(Icons.visibility_rounded, color: _accentColor, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _selectedIds.isEmpty ? null : () => _bulkToggle(false),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.error.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.visibility_off_rounded,
                  color: AdminColors.error, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TOP HEADER ────────────────────────────────────────────
  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: _softShadow,
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: _primaryColor, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Machine Catalog',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: _textPrimary,
                      ),
                    ),
                    if (_isRefreshing) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accentColor,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${_machines.length} machines • $_activeCount active',
                  style: TextStyle(fontSize: 13, color: _textMuted),
                ),
              ],
            ),
          ),
          _buildHeaderIcon(Icons.refresh_rounded, onTap: _loadMachines),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _softShadow,
        ),
        child: Icon(icon, color: _primaryColor, size: 22),
      ),
    );
  }

  // ─── STATS ROW ─────────────────────────────────────────────
  Widget _buildStatsRow() {
    final totalInquiries = _machines.fold<int>(
        0, (sum, m) => sum + ((m['inquiry_count'] ?? 0) as int));
    final totalOwners = _machines.fold<int>(
        0, (sum, m) => sum + ((m['owners_count'] ?? 0) as int));
    final totalRevenue = _machines.fold<double>(
        0, (sum, m) => sum + ((m['total_revenue'] ?? 0) as num).toDouble());

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          _buildStatCard('Machines', '${_machines.length}',
              Icons.inventory_2_rounded, _primaryColor),
          const SizedBox(width: 8),
          _buildStatCard(
              'Owners', '$totalOwners', Icons.people_rounded, _accentColor),
          const SizedBox(width: 8),
          _buildStatCard('Inquiries', '$totalInquiries', Icons.mail_rounded,
              AdminColors.info),
          const SizedBox(width: 8),
          _buildStatCard('Revenue', _formatCurrency(totalRevenue),
              Icons.payments_rounded, AdminColors.warning),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: _isDark ? Border.all(color: _borderColor) : null,
          boxShadow: _cardShadow,
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: _textMuted),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    }
    if (value > 0) {
      return 'Rs. ${value.toStringAsFixed(0)}';
    }
    return 'Rs. 0';
  }

  // ─── SEARCH BAR ────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: _textPrimary),
        onChanged: (_) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            setState(() => _applyFilters());
          });
        },
        decoration: InputDecoration(
          hintText: 'Search name, model, brand, description...',
          hintStyle: TextStyle(color: _textMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: _textMuted, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _applyFilters());
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _elevatedFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.close_rounded, color: _textMuted, size: 18),
                  ),
                )
              : null,
          filled: true,
          fillColor: _cardBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── FILTER CHIPS ──────────────────────────────────────────
  Widget _buildFilterChips() {
    final filters = <Map<String, dynamic>>[
      {
        'key': 'all',
        'label': 'All',
        'count': _machines.length,
        'icon': Icons.apps_rounded,
        'color': _primaryColor,
        'type': 'status',
      },
      {
        'key': 'active',
        'label': 'Active',
        'count': _activeCount,
        'icon': Icons.visibility_rounded,
        'color': _accentColor,
        'type': 'status',
      },
      if (_inactiveCount > 0)
        {
          'key': 'inactive',
          'label': 'Inactive',
          'count': _inactiveCount,
          'icon': Icons.visibility_off_rounded,
          'color': AdminColors.error,
          'type': 'status',
        },
      ..._categories.map((cat) => {
            'key': cat,
            'label': _shortenCategory(cat),
            'count': _machines.where((m) => m['category'] == cat).length,
            'icon': _getCategoryIcon(cat),
            'color': _getCategoryColor(cat),
            'type': 'category',
          }),
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
          final filterType = filter['type'] as String;
          final isSelected = filterType == 'status'
              ? _filterStatus == filter['key'] && _filterCategory == 'all'
              : _filterCategory == filter['key'];
          final color = filter['color'] as Color;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (filterType == 'status') {
                  _filterStatus = filter['key'] as String;
                  _filterCategory = 'all';
                } else {
                  _filterCategory = filter['key'] as String;
                  _filterStatus = 'all';
                }
                _applyFilters();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color : _chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : _borderColor,
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : _isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Brand.royalBlue.withAlpha(8),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
              ),
              child: Row(
                children: [
                  Icon(
                    filter['icon'] as IconData,
                    size: 14,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filter['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : _textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withAlpha(64)
                          : color.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filter['count']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : color,
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

  // ─── RESULTS HEADER WITH SORT ──────────────────────────────
  Widget _buildResultsHeader() {
    if (_isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text(
            '${_filteredMachines.length} ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          Text(
            _filteredMachines.length == _machines.length
                ? 'machines'
                : 'of ${_machines.length} machines',
            style: TextStyle(fontSize: 13, color: _textMuted),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSortOptions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 14, color: _textMuted),
                  const SizedBox(width: 4),
                  Text(
                    _getSortLabel(_sortBy),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) {
                  _selectedIds.clear();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _isSelectionMode ? _primaryColor.withAlpha(26) : _cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 16,
                color: _isSelectionMode ? _primaryColor : _textMuted,
              ),
            ),
          ),
          if (_filterCategory != 'all' ||
              _filterStatus != 'all' ||
              _searchController.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _filterCategory = 'all';
                  _filterStatus = 'all';
                  _sortBy = 'default';
                  _applyFilters();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AdminColors.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded,
                        size: 12, color: AdminColors.error),
                    SizedBox(width: 4),
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'name':
        return 'Name';
      case 'newest':
        return 'Newest';
      case 'oldest':
        return 'Oldest';
      case 'inquiries':
        return 'Inquiries';
      case 'owners':
        return 'Owners';
      default:
        return 'Default';
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...[
                'default',
                'name',
                'newest',
                'oldest',
                'inquiries',
                'owners',
              ].map((sort) {
                final icons = {
                  'default': Icons.reorder_rounded,
                  'name': Icons.sort_by_alpha_rounded,
                  'newest': Icons.arrow_downward_rounded,
                  'oldest': Icons.arrow_upward_rounded,
                  'inquiries': Icons.mail_rounded,
                  'owners': Icons.people_rounded,
                };
                final labels = {
                  'default': 'Display Order',
                  'name': 'Name (A-Z)',
                  'newest': 'Newest First',
                  'oldest': 'Oldest First',
                  'inquiries': 'Most Inquiries',
                  'owners': 'Most Owners',
                };
                final isSelected = _sortBy == sort;

                return ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primaryColor.withAlpha(26)
                          : _elevatedFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icons[sort],
                      size: 18,
                      color: isSelected ? _primaryColor : _textMuted,
                    ),
                  ),
                  title: Text(
                    labels[sort]!,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? _textPrimary : _textSecondary,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: _accentColor,
                          size: 22,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(() {
                      _sortBy = sort;
                      _applyFilters();
                    });
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ─── MACHINE CARD ──────────────────────────────────────────
  Widget _buildMachineCard(Map<String, dynamic> machine) {
    final isActive = machine['is_active'] ?? true;
    final ownersCount = machine['owners_count'] ?? 0;
    final inquiryCount = machine['inquiry_count'] ?? 0;
    final orderCount = machine['order_count'] ?? 0;
    final totalRevenue = machine['total_revenue'] ?? 0;
    final category = machine['category'] ?? '';
    final subCategory = machine['sub_category'] ?? '';
    final categoryColor = _getCategoryColor(category);
    final lastInquiry = machine['last_inquiry_at'];
    final machineId = machine['id'].toString();
    final isSelected = _selectedIds.contains(machineId);
    final imageUrl = machine['image_url'] ??
        (machine['product_images'] != null &&
                (machine['product_images'] as List).isNotEmpty
            ? (machine['product_images'] as List)[0]
            : null);

    return GestureDetector(
      onTap: _isSelectionMode
          ? () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(machineId);
                } else {
                  _selectedIds.add(machineId);
                }
              });
            }
          : () => _viewMachineDetail(machine),
      onLongPress: _isSelectionMode ? null : () => _showMachineActions(machine),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: _primaryColor, width: 2)
              : !isActive
                  ? Border.all(
                      color: AdminColors.error.withAlpha(51), width: 1.5)
                  : _isDark
                      ? Border.all(color: _borderColor)
                      : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryColor.withAlpha(26),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : _cardShadow,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (_isSelectionMode) ...[
                    Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _primaryColor : _elevatedFill,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            isSelected ? null : Border.all(color: _borderColor),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ],
                  // Machine Image
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          categoryColor.withAlpha(20),
                          categoryColor.withAlpha(10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: imageUrl != null && imageUrl.toString().isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl.toString(),
                              fit: BoxFit.cover,
                              width: 70,
                              height: 70,
                              placeholder: (_, __) => Icon(
                                _getCategoryIcon(category),
                                size: 30,
                                color: categoryColor,
                              ),
                              errorWidget: (_, __, ___) => Icon(
                                _getCategoryIcon(category),
                                size: 30,
                                color: categoryColor,
                              ),
                            ),
                          )
                        : Icon(
                            _getCategoryIcon(category),
                            size: 30,
                            color: categoryColor,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                machine['machine_name'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isActive ? _textPrimary : _textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? _accentColor.withAlpha(26)
                                    : AdminColors.error.withAlpha(26),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? _accentColor
                                          : AdminColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isActive
                                          ? _accentColor
                                          : AdminColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          machine['model_number'] ?? '',
                          style: TextStyle(fontSize: 12, color: _textMuted),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _primaryColor.withAlpha(15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                machine['brand'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: categoryColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                subCategory.isNotEmpty
                                    ? subCategory
                                    : _shortenCategory(category),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: categoryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            if (ownersCount > 0)
                              _buildMiniChip(Icons.people_rounded,
                                  '$ownersCount', _accentColor),
                            if (inquiryCount > 0) ...[
                              const SizedBox(width: 5),
                              _buildMiniChip(Icons.mail_rounded,
                                  '$inquiryCount', AdminColors.info),
                            ],
                            if (orderCount > 0) ...[
                              const SizedBox(width: 5),
                              _buildMiniChip(Icons.shopping_cart_rounded,
                                  '$orderCount', AdminColors.warning),
                            ],
                          ],
                        ),
                        if ((totalRevenue as num) > 0 ||
                            lastInquiry != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (totalRevenue > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _accentColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Revenue: ${_formatCurrency((totalRevenue).toDouble())}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: _accentColor,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (lastInquiry != null)
                                Text(
                                  'Last inquiry: ${TimeUtils.getTimeAgo(DateTime.parse(lastInquiry.toString()))}',
                                  style:
                                      TextStyle(fontSize: 9, color: _textMuted),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons
            Container(
              decoration: BoxDecoration(
                color: _elevatedFill,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  _buildActionButton(
                    Icons.edit_rounded,
                    'Edit',
                    _primaryColor,
                    () => _editMachine(machine),
                  ),
                  Container(width: 1, height: 24, color: _dividerColor),
                  _buildActionButton(
                    isActive
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    isActive ? 'Deactivate' : 'Activate',
                    isActive ? AdminColors.error : _accentColor,
                    () => _toggleMachineStatus(machine),
                  ),
                  Container(width: 1, height: 24, color: _dividerColor),
                  _buildActionButton(
                    Icons.more_horiz_rounded,
                    'More',
                    _textSecondary,
                    () => _showMachineActions(machine),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
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

  // ─── MACHINE ACTIONS BOTTOM SHEET ──────────────────────────
  void _showMachineActions(Map<String, dynamic> machine) {
    HapticFeedback.mediumImpact();
    final isActive = machine['is_active'] ?? true;
    final machineName = machine['machine_name'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                machineName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                machine['model_number'] ?? '',
                style: TextStyle(fontSize: 12, color: _textMuted),
              ),
              const SizedBox(height: 16),
              _buildActionTile(
                Icons.info_outline_rounded,
                'View Details',
                'Stats, inquiries, owners',
                _primaryColor,
                () {
                  Navigator.pop(sheetCtx);
                  _viewMachineDetail(machine);
                },
              ),
              _buildActionTile(
                Icons.edit_rounded,
                'Edit Machine',
                'Modify details, specs, images',
                AdminColors.info,
                () {
                  Navigator.pop(sheetCtx);
                  _editMachine(machine);
                },
              ),
              _buildActionTile(
                Icons.copy_rounded,
                'Duplicate',
                'Create a copy of this machine',
                const Color(0xFF8B5CF6),
                () {
                  Navigator.pop(sheetCtx);
                  _duplicateMachine(machine);
                },
              ),
              _buildActionTile(
                isActive
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                isActive ? 'Deactivate' : 'Activate',
                isActive ? 'Hide from customers' : 'Make visible to customers',
                isActive ? AdminColors.warning : _accentColor,
                () {
                  Navigator.pop(sheetCtx);
                  _toggleMachineStatus(machine);
                },
              ),
              _buildActionTile(
                Icons.delete_outline_rounded,
                'Delete',
                'Permanently remove from catalog',
                AdminColors.error,
                () {
                  Navigator.pop(sheetCtx);
                  _deleteMachine(machine);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: _textMuted),
      ),
      trailing:
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _borderColor),
      onTap: onTap,
    );
  }

  // ─── FAB ───────────────────────────────────────────────────
  Widget _buildFAB() {
    return GestureDetector(
      onTap: () => _editMachine(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _accentColor,
              const Color(0xFF8FA52E),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withAlpha(102),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Add Machine',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SKELETON LOADING ──────────────────────────────────────
  Widget _buildLoadingSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      children: [
        Row(
          children: List.generate(
            4,
            (i) => Expanded(
              child: Container(
                height: 80,
                margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: _isDark ? Border.all(color: _borderColor) : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            border: _isDark ? Border.all(color: _borderColor) : null,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: Row(
            children: List.generate(
              4,
              (i) => Container(
                width: 80,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCardElevated : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(
          4,
          (i) => Container(
            height: 160,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(18),
              border: _isDark ? Border.all(color: _borderColor) : null,
            ),
          ),
        ),
      ],
    );
  }

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _buildEmptyState() {
    final hasFilters = _filterCategory != 'all' ||
        _filterStatus != 'all' ||
        _searchController.text.isNotEmpty;

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
                color: _primaryColor.withAlpha(15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                hasFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.inventory_2_outlined,
                size: 40,
                color: _borderColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilters ? 'No machines match' : 'No machines in catalog',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your search or filters'
                  : 'Add your first machine to get started',
              style: TextStyle(fontSize: 13, color: _textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (hasFilters)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _filterCategory = 'all';
                    _filterStatus = 'all';
                    _applyFilters();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accentColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Clear Filters',
                    style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => _editMachine(null),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Add First Machine',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MACHINE DETAIL SHEET
// ═══════════════════════════════════════════════════════════════
class _MachineDetailSheet extends StatefulWidget {
  final String machineId;
  const _MachineDetailSheet({required this.machineId});

  @override
  State<_MachineDetailSheet> createState() => _MachineDetailSheetState();
}

class _MachineDetailSheetState extends State<_MachineDetailSheet> {
  Map<String, dynamic>? _detail;
  bool _isLoading = true;

  // ── Theme helpers for detail sheet ──
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _scaffoldBg => _isDark ? Brand.darkBg : Brand.scaffoldLight;
  Color get _cardBg => _isDark ? Brand.darkCard : Colors.white;
  // ✅ AdminColors.textPrimary does NOT exist → use explicit color
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : Colors.grey.shade400;
  Color get _borderColor => _isDark ? Brand.darkBorder : Colors.grey.shade200;
  Color get _primaryColor =>
      _isDark ? Brand.royalBlueGlow : AdminColors.primary;
  Color get _accentColor =>
      _isDark ? Brand.lightGreenBright : AdminColors.accent;
  List<BoxShadow> get _softShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final result = await SupabaseConfig.client.rpc('get_machine_full_detail',
          params: {'p_machine_id': widget.machineId});
      if (!mounted) return;
      setState(() {
        _detail = result as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      // Fallback to simple select
      try {
        final data = await SupabaseConfig.client
            .from('machine_catalog')
            .select('*')
            .eq('id', widget.machineId)
            .single();
        if (!mounted) return;
        setState(() {
          _detail = {
            'machine': data,
            'stats': {},
            'recent_inquiries': [],
            'owners': [],
          };
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: _primaryColor))
            : _detail == null
                ? Center(
                    child: Text('Machine not found',
                        style: TextStyle(color: _textPrimary)))
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final machine = _detail!['machine'] as Map<String, dynamic>;
    final stats = (_detail!['stats'] ?? {}) as Map<String, dynamic>;
    final inquiries = (_detail!['recent_inquiries'] ?? []) as List;
    final owners = (_detail!['owners'] ?? []) as List;
    final specs = machine['specifications'] as Map<String, dynamic>?;
    final features = machine['features'] as List?;
    final applications = machine['applications'] as List?;
    final imageUrl = machine['image_url'];

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _softShadow,
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: _primaryColor, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine['machine_name'] ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        machine['model_number'] ?? '',
                        style: TextStyle(fontSize: 13, color: _textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Machine Image
        if (imageUrl != null && imageUrl.toString().isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: imageUrl.toString(),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) => Container(
                    color:
                        _isDark ? Brand.darkCardElevated : Colors.grey.shade100,
                    child:
                        Icon(Icons.image_rounded, size: 48, color: _textMuted),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color:
                        _isDark ? Brand.darkCardElevated : Colors.grey.shade100,
                    child: Icon(Icons.broken_image_rounded,
                        size: 48, color: _textMuted),
                  ),
                ),
              ),
            ),
          ),

        // Stats
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatChip('Owners', '${stats['owners_count'] ?? 0}',
                    Icons.people_rounded, _accentColor),
                _buildStatChip('Inquiries', '${stats['total_inquiries'] ?? 0}',
                    Icons.mail_rounded, AdminColors.info),
                _buildStatChip('Orders', '${stats['total_orders'] ?? 0}',
                    Icons.shopping_cart_rounded, AdminColors.warning),
                _buildStatChip('Won', '${stats['won_deals'] ?? 0}',
                    Icons.emoji_events_rounded, _accentColor),
                _buildStatChip('Support', '${stats['support_tickets'] ?? 0}',
                    Icons.build_rounded, const Color(0xFF8B5CF6)),
              ],
            ),
          ),
        ),

        // Specs
        if (specs != null && specs.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Specifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...specs.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                e.key.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value.toString(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),

        // Features
        if (features != null && features.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Features',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: features
                        .map((f) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _accentColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '• ${f.toString()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textPrimary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

        // Applications
        if (applications != null && applications.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: applications
                        .map((a) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _primaryColor.withAlpha(15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                a.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textPrimary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

        // Recent Inquiries
        if (inquiries.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Inquiries (${inquiries.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...inquiries.take(5).map((inq) {
                    final i = inq as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  i['customer_name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (i['company'] != null)
                                  Text(
                                    i['company'].toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (i['sales_stage'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                // ✅ AdminColors.info not Colors.blue
                                color: AdminColors.info.withAlpha(26),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                (i['sales_stage'] as String).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.info,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

        // Owners
        if (owners.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: _isDark ? Border.all(color: _borderColor) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Owners (${owners.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...owners.map((own) {
                    final o = own as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o['name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (o['company'] != null)
                                  Text(
                                    o['company'].toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (o['serial_number'] != null)
                            Text(
                              'S/N: ${o['serial_number']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textMuted,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildStatChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: _textMuted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MACHINE EDITOR PAGE
// ═══════════════════════════════════════════════════════════════
class MachineEditorPage extends StatefulWidget {
  final Map<String, dynamic>? machine;
  const MachineEditorPage({super.key, this.machine});

  @override
  State<MachineEditorPage> createState() => _MachineEditorPageState();
}

class _MachineEditorPageState extends State<MachineEditorPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isEditMode = false;

  // ── Theme getters (not stored fields) ──
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _scaffoldBg => _isDark ? Brand.darkBg : Brand.scaffoldLight;
  Color get _cardBg => _isDark ? Brand.darkCard : Colors.white;
  // ✅ AdminColors.textPrimary does NOT exist
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
  Color get _textSecondary =>
      _isDark ? Brand.darkTextSecondary : Colors.grey.shade600;
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : Colors.grey.shade400;
  Color get _borderColor => _isDark ? Brand.darkBorder : Colors.grey.shade200;
  Color get _elevatedFill =>
      _isDark ? const Color(0xFF22272E) : Colors.grey.shade100;
  Color get _primaryColor =>
      _isDark ? Brand.royalBlueGlow : AdminColors.primary;
  Color get _accentColor =>
      _isDark ? Brand.lightGreenBright : AdminColors.accent;
  List<BoxShadow> get _cardShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];

  // Basic fields
  final _nameController = TextEditingController();
  final _modelController = TextEditingController();
  final _brandController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _brochureUrlController = TextEditingController();
  final _videoUrlController = TextEditingController();
  final _priceController = TextEditingController();
  final _internalPriceController = TextEditingController();
  final _displayOrderController = TextEditingController();

  String? _selectedCategory;
  String? _selectedSubCategory;
  File? _selectedImage;
  String? _uploadedImageUrl;
  bool _isActive = true;

  // ── Gallery (multi-image) state ──────────────────────────────
  // Existing images already saved on the catalog row (loaded in initState
  // for edit mode). New images the admin picks/uploads in this session.
  // Final saved list = _galleryUrls (existing) + uploaded(_galleryFiles).
  List<String> _galleryUrls = [];
  final List<File> _galleryFiles = [];
  final _galleryUrlInputController = TextEditingController();
  bool _galleryUploading = false;

  List<TextEditingController> _featureControllers = [];
  List<TextEditingController> _applicationControllers = [];
  List<TextEditingController> _applicationImageControllers = [];
  List<MapEntry<TextEditingController, TextEditingController>>
      _specControllers = [];

  final categories = [
    'Digital Printers',
    'CNC Routers',
    'Laser Cutters',
    'Finishing Equipment',
  ];

  final subCategories = {
    'Digital Printers': [
      'Eco Solvent',
      'Roll to Roll UV',
      'Flatbed UV',
      'Compact UV',
      'Hybrid UV',
    ],
    'CNC Routers': [
      'Standard',
      'Rotary Attachment',
      'Multi-head',
      'ATC',
    ],
    'Laser Cutters': [
      'CO2 Laser',
      'Fiber Laser',
      'Laser Marking',
      'Laser Welding',
    ],
    'Finishing Equipment': [
      'Laminators',
      'Welders',
      'Eyelet Machines',
      'Cutting Plotters',
    ],
  };

  @override
  void initState() {
    super.initState();
    if (widget.machine != null) {
      _isEditMode = true;
      final m = widget.machine!;
      _nameController.text = m['machine_name'] ?? '';
      _modelController.text = m['model_number'] ?? '';
      _brandController.text = m['brand'] ?? '';
      _selectedCategory = m['category'];
      _selectedSubCategory = m['sub_category'];
      _descriptionController.text = m['description'] ?? '';
      _imageUrlController.text = m['image_url'] ?? '';
      _uploadedImageUrl = m['image_url'];
      // Hydrate the gallery from product_images + legacy images. Dedup
      // while preserving order; drop empty/non-string entries.
      final seen = <String>{};
      void addAll(dynamic arr) {
        if (arr is! List) return;
        for (final v in arr) {
          if (v is String) {
            final t = v.trim();
            if (t.isNotEmpty && seen.add(t)) _galleryUrls.add(t);
          }
        }
      }
      addAll(m['product_images']);
      addAll(m['images']);
      _brochureUrlController.text = m['brochure_url'] ?? '';
      _videoUrlController.text = m['video_url'] ?? '';
      _isActive = m['is_active'] ?? true;

      if (m['price'] != null) {
        _priceController.text = m['price'].toString();
      }
      if (m['internal_price'] != null) {
        _internalPriceController.text = m['internal_price'].toString();
      }
      if (m['display_order'] != null) {
        _displayOrderController.text = m['display_order'].toString();
      }

      final features = m['features'] as List?;
      if (features != null) {
        _featureControllers = features
            .map((f) => TextEditingController(text: f.toString()))
            .toList();
      }

      final apps = m['applications'] as List?;
      if (apps != null) {
        _applicationControllers =
            apps.map((a) => TextEditingController(text: a.toString())).toList();
      }

      // Load application_images — map name → url for quick lookup
      final appImages = m['application_images'] as List?;
      final imageMap = <String, String>{};
      if (appImages != null) {
        for (final img in appImages) {
          if (img is Map) {
            final name = img['name']?.toString() ?? '';
            final url = img['image_url']?.toString() ?? '';
            if (name.isNotEmpty) imageMap[name] = url;
          }
        }
      }
      _applicationImageControllers = _applicationControllers
          .map((c) => TextEditingController(text: imageMap[c.text] ?? ''))
          .toList();

      final specs = m['specifications'] as Map<String, dynamic>?;
      if (specs != null) {
        _specControllers = specs.entries
            .map((e) => MapEntry(
                  TextEditingController(text: e.key),
                  TextEditingController(text: e.value.toString()),
                ))
            .toList();
      }
    }
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose Image Source',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildImageSourceOption(
                    Icons.photo_library_rounded,
                    'Gallery',
                    _primaryColor,
                    () async {
                      Navigator.pop(sheetCtx);
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1200,
                        maxHeight: 1200,
                        imageQuality: 85,
                      );
                      if (pickedFile != null && mounted) {
                        setState(() => _selectedImage = File(pickedFile.path));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildImageSourceOption(
                    Icons.camera_alt_rounded,
                    'Camera',
                    _accentColor,
                    () async {
                      Navigator.pop(sheetCtx);
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.camera,
                        maxWidth: 1200,
                        maxHeight: 1200,
                        imageQuality: 85,
                      );
                      if (pickedFile != null && mounted) {
                        setState(() => _selectedImage = File(pickedFile.path));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSourceOption(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(38)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    try {
      final bytes = await _selectedImage!.readAsBytes();
      if (!mounted) return null;
      final fileExt = _selectedImage!.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'machines/$fileName';
      await SupabaseConfig.client.storage
          .from('product-images')
          .uploadBinary(filePath, bytes);
      if (!mounted) return null;
      return SupabaseConfig.client.storage
          .from('product-images')
          .getPublicUrl(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return null;
    }
  }

  // ── GALLERY (multiple machine images) ────────────────────────
  // Pick one or more device images and append them to the staging list.
  // We don't upload immediately — uploads happen on Save so a cancelled
  // form doesn't leave orphaned blobs in Supabase Storage.
  Future<void> _addGalleryFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _galleryFiles.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _addGalleryFromCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (pickedFile == null || !mounted) return;
    setState(() => _galleryFiles.add(File(pickedFile.path)));
  }

  void _addGalleryFromUrl() {
    final raw = _galleryUrlInputController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a valid image URL (e.g. https://...)'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    if (_galleryUrls.contains(raw)) {
      _galleryUrlInputController.clear();
      return;
    }
    setState(() {
      _galleryUrls.add(raw);
      _galleryUrlInputController.clear();
    });
  }

  void _removeGalleryUrl(String url) {
    setState(() => _galleryUrls.remove(url));
  }

  void _removeGalleryFile(File file) {
    setState(() => _galleryFiles.remove(file));
  }

  // Upload all staged files to Supabase Storage and return their public URLs.
  // Failures are surfaced inline so the admin can retry without losing the
  // rest of the form.
  Future<List<String>> _uploadGalleryFiles() async {
    if (_galleryFiles.isEmpty) return const [];
    setState(() => _galleryUploading = true);
    final results = <String>[];
    try {
      for (final file in _galleryFiles) {
        final bytes = await file.readAsBytes();
        if (!mounted) return results;
        final ext = file.path.split('.').last;
        final name = '${DateTime.now().millisecondsSinceEpoch}'
            '_${results.length}.$ext';
        final path = 'machines/$name';
        await SupabaseConfig.client.storage
            .from('product-images')
            .uploadBinary(path, bytes);
        results.add(SupabaseConfig.client.storage
            .from('product-images')
            .getPublicUrl(path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Some gallery uploads failed: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
    if (mounted) setState(() => _galleryUploading = false);
    return results;
  }

  Widget _buildGallerySection() {
    final totalCount = _galleryUrls.length + _galleryFiles.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_rounded,
                  color: _primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Additional Images ($totalCount)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              if (_galleryUploading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload multiple machine images or paste image URLs (e.g. CDN links). '
            'The first image is used as the main thumbnail when no primary image is set.',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          const SizedBox(height: 12),
          // ── Thumbnails ──
          if (_galleryUrls.isNotEmpty || _galleryFiles.isNotEmpty) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._galleryUrls.map((u) => _galleryThumbForUrl(u)),
                ..._galleryFiles.map((f) => _galleryThumbForFile(f)),
              ],
            ),
            const SizedBox(height: 14),
          ],
          // ── Action buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _galleryUploading ? null : _addGalleryFromGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text('Upload Images',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: BorderSide(color: _primaryColor.withAlpha(102)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _galleryUploading ? null : _addGalleryFromCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text('Camera',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentColor,
                    side: BorderSide(color: _accentColor.withAlpha(102)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── URL paste row ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _galleryUrlInputController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addGalleryFromUrl(),
                  decoration: InputDecoration(
                    hintText: 'Paste image URL (https://...)',
                    prefixIcon: const Icon(Icons.link_rounded, size: 18),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addGalleryFromUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Add',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _galleryThumbForUrl(String url) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 80,
              height: 80,
              color: _borderColor,
              child: Icon(Icons.image_rounded,
                  color: _textSecondary, size: 24),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 80,
              height: 80,
              color: _borderColor,
              child: Icon(Icons.broken_image_rounded,
                  color: AdminColors.error, size: 22),
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: () => _removeGalleryUrl(url),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AdminColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: _cardBg, width: 2),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 12),
            ),
          ),
        ),
        // Tiny "URL" tag so admins can tell URL-added from uploads.
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(140),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('URL',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _galleryThumbForFile(File file) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file, width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: () => _removeGalleryFile(file),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AdminColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: _cardBg, width: 2),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 12),
            ),
          ),
        ),
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(140),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('NEW',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Future<void> _saveMachine() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String? imageUrl = _uploadedImageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
      } else if (_imageUrlController.text.isNotEmpty) {
        imageUrl = _imageUrlController.text.trim();
      }

      // ── Upload staged gallery files, then merge with existing URLs ──
      // (preserves admin's order; uploads append at the end). If no
      // primary image_url was set above, promote the first gallery entry
      // so the catalog row still has a usable thumbnail.
      final newGalleryUploads = await _uploadGalleryFiles();
      if (!mounted) return;
      final mergedGallery = <String>[
        ..._galleryUrls,
        ...newGalleryUploads,
      ];
      // De-dup while preserving order.
      final seenGallery = <String>{};
      final productImages = <String>[];
      // Main image goes first if present, so anything reading
      // product_images[0] gets the canonical thumbnail.
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        seenGallery.add(imageUrl);
        productImages.add(imageUrl);
      }
      for (final u in mergedGallery) {
        if (seenGallery.add(u)) productImages.add(u);
      }
      // Promote first gallery entry to image_url if none provided.
      imageUrl ??=
          productImages.isNotEmpty ? productImages.first : null;

      if (!mounted) return;

      final specs = <String, dynamic>{};
      for (final entry in _specControllers) {
        final key = entry.key.text.trim();
        final val = entry.value.text.trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          specs[key] = val;
        }
      }

      final features = _featureControllers
          .map((c) => c.text.trim())
          .where((f) => f.isNotEmpty)
          .toList();

      final applications = _applicationControllers
          .map((c) => c.text.trim())
          .where((a) => a.isNotEmpty)
          .toList();

      // Build application_images — parallel list of {name, image_url}
      final applicationImages = <Map<String, dynamic>>[];
      for (int i = 0; i < _applicationControllers.length; i++) {
        final name = _applicationControllers[i].text.trim();
        if (name.isEmpty) continue;
        final url = i < _applicationImageControllers.length
            ? _applicationImageControllers[i].text.trim()
            : '';
        applicationImages.add({
          'name': name,
          'image_url': url.isEmpty ? null : url,
        });
      }

      final data = {
        'machine_name': _nameController.text.trim(),
        'model_number': _modelController.text.trim(),
        'brand': _brandController.text.trim(),
        'category': _selectedCategory,
        'sub_category': _selectedSubCategory,
        'description': _descriptionController.text.trim(),
        'image_url': imageUrl,
        // Gallery merged with the primary thumbnail (see logic above).
        'product_images': productImages,
        'brochure_url': _brochureUrlController.text.trim().isEmpty
            ? null
            : _brochureUrlController.text.trim(),
        'video_url': _videoUrlController.text.trim().isEmpty
            ? null
            : _videoUrlController.text.trim(),
        'specifications': specs.isEmpty ? null : specs,
        'features': features.isEmpty ? null : features,
        'applications': applications.isEmpty ? null : applications,
        'application_images': applicationImages,
        'is_active': _isActive,
        'price': _priceController.text.trim().isEmpty
            ? null
            : double.tryParse(_priceController.text.trim()),
        'internal_price': _internalPriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_internalPriceController.text.trim()),
        'display_order': _displayOrderController.text.trim().isEmpty
            ? 0
            : int.tryParse(_displayOrderController.text.trim()) ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isEditMode) {
        await SupabaseConfig.client
            .from('machine_catalog')
            .update(data)
            .eq('id', widget.machine!['id'] as String);
      } else {
        await SupabaseConfig.client.from('machine_catalog').insert(data);
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? 'Machine updated!' : 'Machine added!'),
          backgroundColor: _accentColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            _isDark ? Border.all(color: _borderColor) : null,
                        boxShadow: _cardShadow,
                      ),
                      child: Icon(Icons.close_rounded,
                          color: _primaryColor, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEditMode ? 'Edit Machine' : 'Add New Machine',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isActive ? _accentColor : AdminColors.error,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: _accentColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Image Section ──
                      _buildSectionLabel('Product Image'),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _borderColor,
                              width: 2,
                            ),
                          ),
                          child: _selectedImage != null
                              ? Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Image.file(
                                        _selectedImage!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _selectedImage = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(128),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : _uploadedImageUrl != null &&
                                      _uploadedImageUrl!.isNotEmpty
                                  ? Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          child: CachedNetworkImage(
                                            imageUrl: _uploadedImageUrl!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            placeholder: (_, __) =>
                                                _buildUploadPlaceholder(),
                                            errorWidget: (_, __, ___) =>
                                                _buildUploadPlaceholder(),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.black.withAlpha(128),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.edit_rounded,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Change',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : _buildUploadPlaceholder(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Basic Details ──
                      _buildSectionLabel('Machine Details'),
                      const SizedBox(height: 10),
                      _buildFormField(
                        controller: _nameController,
                        label: 'Machine Name *',
                        icon: Icons.precision_manufacturing_rounded,
                        validator: (v) =>
                            v!.isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormField(
                        controller: _modelController,
                        label: 'Model Number *',
                        icon: Icons.tag_rounded,
                        validator: (v) =>
                            v!.isEmpty ? 'Model is required' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormField(
                        controller: _brandController,
                        label: 'Brand *',
                        icon: Icons.business_rounded,
                        validator: (v) =>
                            v!.isEmpty ? 'Brand is required' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        value: _selectedCategory,
                        label: 'Category *',
                        icon: Icons.category_rounded,
                        items: categories,
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                            _selectedSubCategory = null;
                          });
                        },
                        validator: (v) =>
                            v == null ? 'Category is required' : null,
                      ),
                      const SizedBox(height: 12),
                      if (_selectedCategory != null &&
                          subCategories[_selectedCategory] != null) ...[
                        _buildDropdownField(
                          value: _selectedSubCategory,
                          label: 'Sub-Category',
                          icon: Icons.subdirectory_arrow_right_rounded,
                          items: subCategories[_selectedCategory]!,
                          onChanged: (value) =>
                              setState(() => _selectedSubCategory = value),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildFormField(
                        controller: _descriptionController,
                        label: 'Description',
                        icon: Icons.description_rounded,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 24),

                      // ── Specifications ──
                      _buildDynamicSection(
                        title: 'Specifications',
                        subtitle: 'Key-value pairs (e.g. Print Width → 1.7m)',
                        icon: Icons.settings_rounded,
                        isKeyValue: true,
                      ),
                      const SizedBox(height: 24),

                      // ── Features ──
                      _buildDynamicListSection(
                        title: 'Features',
                        subtitle: 'Key selling points',
                        icon: Icons.star_rounded,
                        controllers: _featureControllers,
                        onAdd: () => setState(() =>
                            _featureControllers.add(TextEditingController())),
                        onRemove: (i) => setState(() {
                          _featureControllers[i].dispose();
                          _featureControllers.removeAt(i);
                        }),
                        hint: 'e.g. Epson i3200 print heads',
                      ),
                      const SizedBox(height: 24),

                      // ── Applications ──
                      _buildApplicationsSection(),
                      const SizedBox(height: 24),

                      // ── URLs ──
                      _buildSectionLabel('Resources & Links'),
                      const SizedBox(height: 10),
                      _buildFormField(
                        controller: _imageUrlController,
                        label: 'Image URL (optional)',
                        icon: Icons.link_rounded,
                        hint: 'https://example.com/image.jpg',
                      ),
                      const SizedBox(height: 12),
                      // ── Gallery (multi-upload + URL paste) ──
                      // Single primary image (above) remains the thumbnail.
                      // This section adds an arbitrary number of additional
                      // catalog images that get saved into product_images[].
                      _buildGallerySection(),
                      const SizedBox(height: 12),
                      _buildFormField(
                        controller: _brochureUrlController,
                        label: 'Brochure URL',
                        icon: Icons.picture_as_pdf_rounded,
                        hint: 'https://example.com/brochure.pdf',
                      ),
                      const SizedBox(height: 12),
                      _buildFormField(
                        controller: _videoUrlController,
                        label: 'Video URL',
                        icon: Icons.videocam_rounded,
                        hint: 'https://youtube.com/watch?v=...',
                      ),
                      const SizedBox(height: 24),

                      // ── Admin Fields ──
                      _buildSectionLabel('Admin Settings'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildFormField(
                              controller: _priceController,
                              label: 'Public Price',
                              icon: Icons.sell_rounded,
                              hint: '0.00',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildFormField(
                              controller: _internalPriceController,
                              label: 'Internal Price',
                              icon: Icons.attach_money_rounded,
                              hint: '0.00',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFormField(
                        controller: _displayOrderController,
                        label: 'Display Order',
                        icon: Icons.reorder_rounded,
                        hint: '0',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 32),

                      // ── Save Button ──
                      GestureDetector(
                        onTap: _isLoading ? null : _saveMachine,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _accentColor,
                                const Color(0xFF8FA52E),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _accentColor.withAlpha(102),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isEditMode
                                            ? Icons.check_rounded
                                            : Icons.add_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isEditMode
                                            ? 'Update Machine'
                                            : 'Add Machine',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DYNAMIC SPEC SECTION ──────────────────────────────────
  Widget _buildDynamicSection({
    required String title,
    required String subtitle,
    required IconData icon,
    bool isKeyValue = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel(title),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() {
                  _specControllers.add(MapEntry(
                    TextEditingController(),
                    TextEditingController(),
                  ));
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: _accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: _textMuted),
        ),
        const SizedBox(height: 10),
        ..._specControllers.asMap().entries.map(
          (entry) {
            final i = entry.key;
            final kv = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildFormField(
                      controller: kv.key,
                      label: 'Key',
                      icon: Icons.vpn_key_rounded,
                      hint: 'print_width',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _buildFormField(
                      controller: kv.value,
                      label: 'Value',
                      icon: Icons.text_fields_rounded,
                      hint: '1.7m',
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _specControllers[i].key.dispose();
                        _specControllers[i].value.dispose();
                        _specControllers.removeAt(i);
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AdminColors.error.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: AdminColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (_specControllers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _elevatedFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Text(
              'No specifications added yet. Tap "Add" to add key-value pairs.',
              style: TextStyle(fontSize: 12, color: _textMuted),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  // ─── DYNAMIC LIST SECTION ──────────────────────────────────
  Widget _buildDynamicListSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<TextEditingController> controllers,
    required VoidCallback onAdd,
    required Function(int) onRemove,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel(title),
            const Spacer(),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: _accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: _textMuted),
        ),
        const SizedBox(height: 10),
        ...controllers.asMap().entries.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildFormField(
                    controller: entry.value,
                    label:
                        '${title.substring(0, title.length - 1)} ${entry.key + 1}',
                    icon: icon,
                    hint: hint,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onRemove(entry.key),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AdminColors.error.withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.remove_rounded,
                      size: 16,
                      color: AdminColors.error,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (controllers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _elevatedFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Text(
              'No $title added yet. Tap "Add" to start.',
              style: TextStyle(fontSize: 12, color: _textMuted),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  // ─── APPLICATIONS + IMAGE URLS SECTION ────────────────────
  Widget _buildApplicationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel('Applications'),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() {
                _applicationControllers.add(TextEditingController());
                _applicationImageControllers.add(TextEditingController());
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: _accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(
          'What this machine is used for (+ optional image URLs)',
          style: TextStyle(fontSize: 12, color: _textMuted),
        ),
        const SizedBox(height: 10),
        ..._applicationControllers.asMap().entries.map((entry) {
          final i = entry.key;
          // Ensure image controller list is always in sync
          while (_applicationImageControllers.length <= i) {
            _applicationImageControllers.add(TextEditingController());
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                // ── Name row ──
                Row(
                  children: [
                    Expanded(
                      child: _buildFormField(
                        controller: entry.value,
                        label: 'Application ${i + 1}',
                        icon: Icons.apps_rounded,
                        hint: 'e.g. Banners, Signage',
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() {
                        _applicationControllers[i].dispose();
                        _applicationControllers.removeAt(i);
                        _applicationImageControllers[i].dispose();
                        _applicationImageControllers.removeAt(i);
                      }),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AdminColors.error.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.remove_rounded,
                          size: 16,
                          color: AdminColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ── Image URL row ──
                Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildFormField(
                        controller: _applicationImageControllers[i],
                        label: 'Image URL (optional)',
                        icon: Icons.image_rounded,
                        hint: 'https://example.com/app-photo.jpg',
                      ),
                    ),
                    const SizedBox(width: 38), // align with remove button width
                  ],
                ),
              ],
            ),
          );
        }),
        if (_applicationControllers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _elevatedFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Text(
              'No Applications added yet. Tap "Add" to start.',
              style: TextStyle(fontSize: 12, color: _textMuted),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: _textPrimary,
      ),
    );
  }

  Widget _buildUploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _primaryColor.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.cloud_upload_rounded, size: 28, color: _textMuted),
        ),
        const SizedBox(height: 12),
        Text(
          'Tap to upload image',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'JPG, PNG up to 5MB',
          style: TextStyle(fontSize: 12, color: _textMuted),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        keyboardType: keyboardType,
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: _textMuted),
          hintStyle: TextStyle(color: _textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: _textMuted, size: 20),
          filled: true,
          fillColor: _cardBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _primaryColor, width: 1.5),
          ),
          // ✅ AdminColors.error not Colors.red
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AdminColors.error, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        dropdownColor: _cardBg,
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _textMuted),
          prefixIcon: Icon(icon, color: _textMuted, size: 20),
          filled: true,
          fillColor: _cardBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, style: TextStyle(color: _textPrimary)),
                ))
            .toList(),
        onChanged: onChanged,
        validator: validator,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    _brandController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _galleryUrlInputController.dispose();
    _brochureUrlController.dispose();
    _videoUrlController.dispose();
    _priceController.dispose();
    _internalPriceController.dispose();
    _displayOrderController.dispose();
    for (final c in _featureControllers) {
      c.dispose();
    }
    for (final c in _applicationControllers) {
      c.dispose();
    }
    for (final c in _applicationImageControllers) {
      c.dispose();
    }
    for (final e in _specControllers) {
      e.key.dispose();
      e.value.dispose();
    }
    super.dispose();
  }
}
