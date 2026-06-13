// lib/screens/customer/my_machines_page.dart
//
// ═══════════════════════════════════════════════════════════
//  FIXES APPLIED (v19 audit):
//   [FIX-1]  Removed import app_theme.dart (AppTheme is DEAD)
//   [FIX-2]  Removed Provider.of<AppTheme> → Theme.of(context)
//   [FIX-3]  Deleted duplicate _B class → uses Brand from brand_colors.dart
//   [FIX-4]  All _B.xxx → Brand.xxx (~170 replacements)
//   [FIX-5]  All Image.network → CachedNetworkImage
//   [FIX-6]  All .withOpacity() → .withAlpha()
//   [FIX-7]  PageRouteBuilder → MaterialPageRoute
//   [FIX-8]  Direct map mutation → spread copy
//   [FIX-9]  Bottom sheet radius 24 → 28
//   [FIX-10] Removed unused l10n import
//   [FIX-11] Added CachedNetworkImage import
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../widgets/common/ic_icons.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';
import 'register_machine_page.dart';
import 'my_machine_detail_page.dart';
import '../../widgets/ds/ds_widgets.dart';

class MyMachinesPage extends StatefulWidget {
  final bool showNavBar;
  const MyMachinesPage({super.key, this.showNavBar = true});

  @override
  State<MyMachinesPage> createState() => _MyMachinesPageState();
}

class _MyMachinesPageState extends State<MyMachinesPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;
  bool _hasError = false;

  String _filterStatus = 'all';
  bool _isGridView = false;
  String _searchQuery = '';
  bool _isSearchVisible = false;
  String _sortBy = 'recent';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _fabAnimController;
  late Animation<double> _fabAnimation;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    _loadMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadMachines() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final data =
          await SupabaseConfig.client.from('customer_machines').select('''
            *,
            machine_catalog!customer_machines_catalog_machine_id_fkey(
              machine_name,
              model_number,
              brand,
              category,
              sub_category,
              image_url,
              images,
              description,
              specifications
            )
          ''').eq('user_id', userId).order('purchase_date', ascending: false);

      if (mounted) {
        setState(() {
          _machines = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        _fabAnimController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;

        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredAndSortedMachines {
    var filtered = List<Map<String, dynamic>>.from(_machines);

    if (_filterStatus != 'all') {
      filtered = filtered.where((m) => m['status'] == _filterStatus).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        final catalog = m['machine_catalog'] as Map<String, dynamic>?;
        final name = (catalog?['machine_name'] ?? '').toString().toLowerCase();
        final brand = (catalog?['brand'] ?? '').toString().toLowerCase();
        final model = (catalog?['model_number'] ?? '').toString().toLowerCase();
        final serial = (m['serial_number'] ?? '').toString().toLowerCase();
        final nickname = (m['machine_nickname'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            brand.contains(query) ||
            model.contains(query) ||
            serial.contains(query) ||
            nickname.contains(query);
      }).toList();
    }

    filtered.sort((a, b) {
      final aFav = (a['is_favorite'] == true) ? 0 : 1;
      final bFav = (b['is_favorite'] == true) ? 0 : 1;
      if (aFav != bFav) return aFav.compareTo(bFav);

      switch (_sortBy) {
        case 'name':
          final aName = (a['machine_catalog']
                  as Map<String, dynamic>?)?['machine_name'] ??
              '';
          final bName = (b['machine_catalog']
                  as Map<String, dynamic>?)?['machine_name'] ??
              '';
          return aName.toString().compareTo(bName.toString());
        case 'warranty':
          final aDays = _getWarrantyDaysLeft(
              a['warranty_end_date'] ?? a['warranty_expiry']);
          final bDays = _getWarrantyDaysLeft(
              b['warranty_end_date'] ?? b['warranty_expiry']);
          return aDays.compareTo(bDays);
        case 'status':
          final order = {'active': 0, 'service': 1, 'inactive': 2};
          return (order[a['status']] ?? 3).compareTo(order[b['status']] ?? 3);
        case 'recent':
        default:
          final aDate = a['purchase_date'] ?? '';
          final bDate = b['purchase_date'] ?? '';
          return bDate.toString().compareTo(aDate.toString());
      }
    });

    return filtered;
  }

  int _getStatusCount(String status) {
    if (status == 'all') return _machines.length;
    return _machines.where((m) => m['status'] == status).length;
  }

  String? _getMachineImageUrl(Map<String, dynamic> machine) {
    final catalog = machine['machine_catalog'] as Map<String, dynamic>?;
    if (catalog == null) return null;
    if (catalog['images'] != null && (catalog['images'] as List).isNotEmpty) {
      return (catalog['images'] as List)[0]?.toString();
    }
    if (catalog['image_url'] != null &&
        catalog['image_url'].toString().isNotEmpty) {
      return catalog['image_url'].toString();
    }
    return null;
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
        return Icons.settings_suggest_rounded;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      final months = [
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
        'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  bool _isWarrantyValid(String? expiryDate) {
    if (expiryDate == null) return false;
    try {
      return DateTime.parse(expiryDate).isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  int _getWarrantyDaysLeft(String? expiryDate) {
    if (expiryDate == null) return 0;
    try {
      return DateTime.parse(expiryDate).difference(DateTime.now()).inDays;
    } catch (e) {
      return 0;
    }
  }

  double _getWarrantyProgress(Map<String, dynamic> machine) {
    final purchaseDate = machine['purchase_date'];
    final warrantyDate =
        machine['warranty_end_date'] ?? machine['warranty_expiry'];
    if (purchaseDate == null || warrantyDate == null) return 0;
    try {
      final start = DateTime.parse(purchaseDate);
      final end = DateTime.parse(warrantyDate);
      final now = DateTime.now();
      final total = end.difference(start).inDays;
      final elapsed = now.difference(start).inDays;
      if (total <= 0) return 0;
      return (elapsed / total).clamp(0.0, 1.0);
    } catch (e) {
      return 0;
    }
  }

  bool _isServiceDueSoon(Map<String, dynamic> machine) {
    final nextService = machine['next_service_due'];
    if (nextService == null) return false;
    try {
      final serviceDate = DateTime.parse(nextService);
      final daysUntil = serviceDate.difference(DateTime.now()).inDays;
      return daysUntil <= 7 && daysUntil >= 0;
    } catch (e) {
      return false;
    }
  }

  bool _isServiceOverdue(Map<String, dynamic> machine) {
    final nextService = machine['next_service_due'];
    if (nextService == null) return false;
    try {
      return DateTime.parse(nextService).isBefore(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status) {
      case 'active':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'service':
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);
      case 'inactive':
        return isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935);
      default:
        return isDark ? Brand.darkTextSecondary : Colors.grey;
    }
  }

  Color _getStatusFilterColor(String status, bool isDark) {
    switch (status) {
      case 'all':
        return isDark ? Brand.darkIconActive : Brand.royalBlue;
      case 'active':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'service':
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);
      case 'inactive':
        return isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935);
      default:
        return isDark ? Brand.darkTextSecondary : Colors.grey;
    }
  }

  Map<String, Map<String, dynamic>> _getStatusConfig(bool isDark) => {
        'all': {
          'label': S.of(context)!.commonAll,
          'icon': Icons.list_alt_rounded,
          'color': _getStatusFilterColor('all', isDark),
        },
        'active': {
          'label': S.of(context)!.machineActive,
          'icon': Icons.check_circle_rounded,
          'color': _getStatusFilterColor('active', isDark),
        },
        'service': {
          'label': S.of(context)!.machineInService,
          'icon': Icons.build_rounded,
          'color': _getStatusFilterColor('service', isDark),
        },
        'inactive': {
          'label': S.of(context)!.machineInactive,
          'icon': Icons.cancel_rounded,
          'color': _getStatusFilterColor('inactive', isDark),
        },
      };

  Future<void> _toggleFavorite(Map<String, dynamic> machine) async {
    HapticFeedback.lightImpact();
    final machineId = machine['id'];
    final currentFav = machine['is_favorite'] == true;

    // ✅ FIX-8: spread copy instead of direct map mutation
    final idx = _machines.indexWhere((m) => m['id'] == machineId);
    if (idx != -1) {
      setState(() {
        _machines[idx] = {..._machines[idx], 'is_favorite': !currentFav};
      });
    }

    try {
      await SupabaseConfig.client.from('customer_machines').update({
        'is_favorite': !currentFav,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', machineId);
    } catch (e) {
      if (mounted) {
        // Rollback with spread copy
        final rollbackIdx = _machines.indexWhere((m) => m['id'] == machineId);
        if (rollbackIdx != -1) {
          setState(() {
            _machines[rollbackIdx] = {
              ..._machines[rollbackIdx],
              'is_favorite': currentFav,
            };
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update favorite: $e')),
        );
      }
    }
  }

  void _showSortOptions(bool isDark) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _buildSortSheet(isDark),
    );
  }

  void _showMachineActions(Map<String, dynamic> machine, bool isDark) {
    HapticFeedback.mediumImpact();
    final catalog = machine['machine_catalog'] as Map<String, dynamic>?;
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _buildMachineActionsSheet(machine, catalog, isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIX-2: Use Theme.of(context) instead of dead AppTheme provider
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Navy hero sits behind the status bar in both modes.
      value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor:
              Brand.canvas(isDark)),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildTopBar(isDark),
              if (!_isLoading && !_hasError && _machines.isNotEmpty) ...[
                _buildSummaryCards(isDark),
                _buildAlertBanner(isDark),
                _buildStatusFilter(isDark),
                _buildResultBar(isDark),
              ],
              Expanded(
                child: _isLoading
                    ? _buildSkeletonLoading(isDark)
                    : _hasError
                        ? _buildErrorState(isDark)
                        : _filteredAndSortedMachines.isEmpty
                            ? _buildEmptyState(isDark)
                            : _buildMachineList(isDark),
              ),
            ],
          ),
        ),
        floatingActionButton: _isLoading
            ? null
            : ScaleTransition(
                scale: _fabAnimation,
                child: _buildFAB(isDark),
              ),
        bottomNavigationBar: widget.showNavBar
            ? CustomerNavBar(
                currentIndex: 1,
                onTabSelected: CustomerNavController.switchTab,
              )
            : null,
      ),
    );
  }

  // ─── TOP BAR — Navy Glow hero ──────────────────────────────

  Widget _buildTopBar(bool isDark) {
    return DsPageHeader(
      title: S.of(context)!.machineTitle,
      subtitle: _isLoading
          ? null
          : '${_machines.length} registered machine${_machines.length != 1 ? 's' : ''}',
      showBack: !widget.showNavBar,
      actions: [
        _heroButton(
          Icons.search_rounded,
          active: _isSearchVisible,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _isSearchVisible = !_isSearchVisible;
              if (!_isSearchVisible) {
                _searchController.clear();
                _searchQuery = '';
              } else {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _searchFocusNode.requestFocus();
                });
              }
            });
          },
        ),
        const SizedBox(width: 6),
        _heroButton(
          _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isGridView = !_isGridView);
          },
        ),
        const SizedBox(width: 6),
        _heroButton(Icons.sort_rounded, onTap: () => _showSortOptions(isDark)),
      ],
      bottom: _isSearchVisible ? _buildSearchBar(isDark) : null,
    );
  }

  /// Frosted action button that sits on the navy hero.
  Widget _heroButton(IconData icon,
      {required VoidCallback onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active
              ? Brand.lime.withAlpha(46)
              : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? Brand.lime : const Color(0xFF2A3F6E),
          ),
        ),
        child: Icon(icon,
            color: active ? Brand.lime : Colors.white, size: 19),
      ),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────

  /// Search field styled for the navy hero `bottom` slot.
  Widget _buildSearchBar(bool isDark) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: const TextStyle(color: Colors.white, fontSize: 12.5),
      cursorColor: Brand.lime,
      decoration: InputDecoration(
        hintText: 'Search by name, brand, serial number...',
        hintStyle:
            const TextStyle(color: Color(0xFF8FA3C8), fontSize: 12.5),
        prefixIcon: const Icon(Icons.search_rounded,
            color: Color(0xFF8FA3C8), size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Icon(Icons.close_rounded,
                    color: Color(0xFF8FA3C8), size: 18),
              )
            : null,
        filled: true,
        fillColor: const Color(0xD916294F),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3F6E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3F6E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.lime, width: 1.5),
        ),
      ),
    );
  }

  // ─── ALERT BANNER ──────────────────────────────────────────

  Widget _buildAlertBanner(bool isDark) {
    final serviceDue = _machines.where((m) => _isServiceDueSoon(m)).toList();
    final serviceOverdue =
        _machines.where((m) => _isServiceOverdue(m)).toList();
    final warrantyExpiring = _machines.where((m) {
      final days =
          _getWarrantyDaysLeft(m['warranty_end_date'] ?? m['warranty_expiry']);
      return days > 0 && days <= 30;
    }).toList();

    if (serviceDue.isEmpty &&
        serviceOverdue.isEmpty &&
        warrantyExpiring.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(children: [
        if (serviceOverdue.isNotEmpty)
          _buildAlertItem(
              Icons.error_rounded,
              '${serviceOverdue.length} machine${serviceOverdue.length > 1 ? 's' : ''} overdue for service',
              isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935),
              isDark),
        if (serviceDue.isNotEmpty)
          _buildAlertItem(
              Icons.schedule_rounded,
              '${serviceDue.length} machine${serviceDue.length > 1 ? 's' : ''} due for service this week',
              isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800),
              isDark),
        if (warrantyExpiring.isNotEmpty)
          _buildAlertItem(
              Icons.warning_amber_rounded,
              '${warrantyExpiring.length} warranty${warrantyExpiring.length > 1 ? 'ies' : 'y'} expiring within 30 days',
              isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800),
              isDark),
      ]),
    );
  }

  Widget _buildAlertItem(IconData icon, String text, Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : color.withAlpha(13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(isDark ? 38 : 51)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 31 : 26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
        Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: color.withAlpha(128)),
      ]),
    );
  }

  // ─── SUMMARY CARDS ─────────────────────────────────────────

  Widget _buildSummaryCards(bool isDark) {
    final active = _getStatusCount('active');
    final service = _getStatusCount('service');
    final warrantyExpiring = _machines.where((m) {
      final days =
          _getWarrantyDaysLeft(m['warranty_end_date'] ?? m['warranty_expiry']);
      return days > 0 && days <= 30;
    }).length;

    // Stat tiles overlap the hero's curved bottom edge (Navy Glow signature).
    return DsStatRow(
      tiles: [
        DsStatTile(
          icon: Icons.precision_manufacturing_rounded,
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          value: '${_machines.length}',
          label: 'Total',
        ),
        DsStatTile(
          icon: Icons.check_circle_rounded,
          color: StatusColors.success,
          value: '$active',
          label: 'Active',
        ),
        DsStatTile(
          icon: Icons.build_rounded,
          color: StatusColors.inProgress,
          value: '$service',
          label: 'Service',
        ),
        DsStatTile(
          icon: Icons.warning_rounded,
          color: warrantyExpiring > 0
              ? StatusColors.danger
              : StatusColors.closed,
          value: '$warrantyExpiring',
          label: 'Expiring',
        ),
      ],
    );
  }

  // ─── STATUS FILTER ─────────────────────────────────────────

  Widget _buildStatusFilter(bool isDark) {
    final statuses = ['all', 'active', 'service', 'inactive'];
    final statusConfig = _getStatusConfig(isDark);

    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 14),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: statuses.length,
        itemBuilder: (context, index) {
          final status = statuses[index];
          final config = statusConfig[status]!;
          final isSelected = _filterStatus == status;
          final count = _getStatusCount(status);
          final color = config['color'] as Color;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filterStatus = status);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color
                    : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(14),
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
                            offset: const Offset(0, 2)),
                      ]
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(config['icon'] as IconData,
                    size: 16, color: isSelected ? Colors.white : color),
                const SizedBox(width: 6),
                Text(config['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    )),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withAlpha(64)
                          : color.withAlpha(isDark ? 31 : 26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : color)),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  // ─── RESULT BAR ────────────────────────────────────────────

  Widget _buildResultBar(bool isDark) {
    final machines = _filteredAndSortedMachines;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(children: [
        RichText(
          text: TextSpan(children: [
            TextSpan(
                text: '${machines.length} ',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            TextSpan(
                text: machines.length == 1 ? 'Machine' : 'Machines',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
          ]),
        ),
        if (_searchQuery.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkIconActive.withAlpha(26)
                    : Brand.royalBlue.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('"$_searchQuery"',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        const Spacer(),
        if (_filterStatus != 'all' || _searchQuery.isNotEmpty)
          GestureDetector(
            onTap: () {
              setState(() {
                _filterStatus = 'all';
                _searchQuery = '';
                _searchController.clear();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(isDark ? 31 : 15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withAlpha(38)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close_rounded,
                    size: 16,
                    color:
                        isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400),
                const SizedBox(width: 4),
                Text(S.of(context)!.commonClear,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFFF6B6B)
                            : Colors.red.shade400)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ─── MACHINE LIST ──────────────────────────────────────────

  Widget _buildMachineList(bool isDark) {
    final machines = _filteredAndSortedMachines;
    return RefreshIndicator(
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: Brand.surface(isDark),
      onRefresh: _loadMachines,
      child: _isGridView
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72),
              itemCount: machines.length,
              itemBuilder: (context, index) => _buildAnimatedItem(
                  index, _buildMachineGridCard(machines[index], isDark)),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: machines.length,
              itemBuilder: (context, index) => _buildAnimatedItem(
                  index, _buildDismissibleCard(machines[index], isDark)),
            ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index.clamp(0, 10) * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: child,
    );
  }

  // ─── DISMISSIBLE WRAPPER ──────────────────────────────────

  Widget _buildDismissibleCard(Map<String, dynamic> machine, bool isDark) {
    final isFav = machine['is_favorite'] == true;

    return Dismissible(
      key: Key(machine['id'].toString()),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          _navigateToDetail(machine);
          return false;
        } else {
          await _toggleFavorite(machine);
          return false;
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isFav
              ? (isDark ? Brand.darkTextSecondary : Colors.grey.shade400)
              : const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isFav ? Icons.star_border_rounded : Icons.star_rounded,
              color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Text(isFav ? S.of(context)!.machineUnfavorite : S.of(context)!.machineFavorite,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(S.of(context)!.machineViewDetails,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24),
        ]),
      ),
      child: _buildMachineListCard(machine, isDark),
    );
  }

  // ✅ FIX-7: MaterialPageRoute instead of PageRouteBuilder
  void _navigateToDetail(Map<String, dynamic> machine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyMachineDetailPage(machine: machine),
      ),
    ).then((_) {
      if (mounted) _loadMachines();
    });
  }

  // ─── LIST CARD ─────────────────────────────────────────────

  Widget _buildMachineListCard(Map<String, dynamic> machine, bool isDark) {
    final catalog = machine['machine_catalog'] as Map<String, dynamic>?;
    final status = (machine['status'] ?? 'active').toString();
    final statusColor = _getStatusColor(status, isDark);
    final imageUrl = _getMachineImageUrl(machine);
    final warrantyDate =
        machine['warranty_end_date'] ?? machine['warranty_expiry'];
    final hasWarranty = warrantyDate != null;
    final warrantyValid = _isWarrantyValid(warrantyDate?.toString());
    final warrantyDays = _getWarrantyDaysLeft(warrantyDate?.toString());
    final warrantyProgress = _getWarrantyProgress(machine);
    final isFav = machine['is_favorite'] == true;
    final isOverdue = _isServiceOverdue(machine);
    final isDueSoon = _isServiceDueSoon(machine);
    final nickname = machine['machine_nickname'];

    return GestureDetector(
      onTap: () => _navigateToDetail(machine),
      onLongPress: () => _showMachineActions(machine, isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOverdue
                ? (isDark
                    ? const Color(0xFFFF6B6B).withAlpha(77)
                    : const Color(0xFFE53935).withAlpha(102))
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Brand.royalBlue.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: Column(children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isOverdue
                    ? [
                        isDark
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFFE53935),
                        isDark
                            ? const Color(0xFFFF6B6B).withAlpha(153)
                            : const Color(0xFFFF5252)
                      ]
                    : [statusColor, statusColor.withAlpha(128)],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isDark ? Brand.darkBorderLight : Brand.borderLight,
                        width: 1),
                  ),
                  // ✅ FIX-5: CachedNetworkImage instead of Image.network
                  child: imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            width: 76,
                            height: 76,
                            placeholder: (_, __) => _buildMachineIconFallback(
                                catalog?['category'], isDark),
                            errorWidget: (_, __, ___) =>
                                _buildMachineIconFallback(
                                    catalog?['category'], isDark),
                          ),
                        )
                      : _buildMachineIconFallback(catalog?['category'], isDark),
                ),
                if (isFav)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Brand.surface(isDark),
                            width: 2),
                      ),
                      child: const Icon(Icons.star_rounded,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (nickname != null &&
                                    nickname.toString().isNotEmpty)
                                  Text(nickname.toString(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Brand.darkIconActive
                                              : Brand.royalBlue,
                                          fontWeight: FontWeight.w600)),
                                Text(
                                    catalog?['machine_name'] ??
                                        'Unknown Machine',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ]),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(isDark ? 31 : 20),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: statusColor.withAlpha(38)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(status.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    letterSpacing: 0.3)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      if (catalog?['brand'] != null)
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: isDark
                                    ? Brand.darkIconActive.withAlpha(26)
                                    : Brand.royalBlue.withAlpha(20),
                                borderRadius: BorderRadius.circular(5)),
                            child: Text(catalog!['brand'].toString(),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Brand.darkIconActive
                                        : Brand.royalBlue)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'S/N: ${machine['serial_number'] ?? 'N/A'}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 13,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight),
                        const SizedBox(width: 4),
                        Text(_formatDate(machine['purchase_date']?.toString()),
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)),
                        if (hasWarranty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.verified_user_rounded,
                              size: 13,
                              color: warrantyValid
                                  ? (isDark
                                      ? Brand.lightGreenBright
                                      : Brand.lightGreen)
                                  : (isDark
                                      ? const Color(0xFFFF6B6B)
                                      : Colors.red.shade400)),
                          const SizedBox(width: 4),
                          Text(
                              warrantyValid
                                  ? '${warrantyDays}d left'
                                  : 'Expired',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: warrantyValid
                                      ? (isDark
                                          ? Brand.lightGreenBright
                                          : Brand.lightGreen)
                                      : (isDark
                                          ? const Color(0xFFFF6B6B)
                                          : Colors.red.shade400))),
                        ],
                      ]),
                      if (hasWarranty && warrantyValid) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: warrantyProgress,
                            minHeight: 3,
                            backgroundColor: isDark
                                ? Brand.darkBorderLight.withAlpha(102)
                                : Brand.subtleLight.withAlpha(26),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                warrantyDays <= 30
                                    ? (isDark
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFFFF9800))
                                    : (isDark
                                        ? Brand.lightGreenBright
                                        : Brand.lightGreen)),
                          ),
                        ),
                      ],
                      if (isOverdue || isDueSoon) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isOverdue
                                    ? (isDark
                                        ? const Color(0xFFFF6B6B)
                                        : const Color(0xFFE53935))
                                    : (isDark
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFFFF9800)))
                                .withAlpha(isDark ? 26 : 20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                                isOverdue
                                    ? Icons.error_outline_rounded
                                    : Icons.schedule_rounded,
                                size: 12,
                                color: isOverdue
                                    ? (isDark
                                        ? const Color(0xFFFF6B6B)
                                        : const Color(0xFFE53935))
                                    : (isDark
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFFFF9800))),
                            const SizedBox(width: 4),
                            Text(
                                isOverdue
                                    ? 'Service overdue!'
                                    : 'Service due soon',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isOverdue
                                        ? (isDark
                                            ? const Color(0xFFFF6B6B)
                                            : const Color(0xFFE53935))
                                        : (isDark
                                            ? const Color(0xFFFFB74D)
                                            : const Color(0xFFFF9800)))),
                          ]),
                        ),
                      ],
                    ]),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: isDark
                        ? Brand.darkTextTertiary
                        : Brand.royalBlue.withAlpha(89)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─── GRID CARD ─────────────────────────────────────────────

  Widget _buildMachineGridCard(Map<String, dynamic> machine, bool isDark) {
    final catalog = machine['machine_catalog'] as Map<String, dynamic>?;
    final status = (machine['status'] ?? 'active').toString();
    final statusColor = _getStatusColor(status, isDark);
    final imageUrl = _getMachineImageUrl(machine);
    final warrantyDate =
        machine['warranty_end_date'] ?? machine['warranty_expiry'];
    final warrantyValid = _isWarrantyValid(warrantyDate?.toString());
    final isFav = machine['is_favorite'] == true;
    final isOverdue = _isServiceOverdue(machine);

    return GestureDetector(
      onTap: () => _navigateToDetail(machine),
      onLongPress: () => _showMachineActions(machine, isDark),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOverdue
                ? (isDark
                    ? const Color(0xFFFF6B6B).withAlpha(77)
                    : const Color(0xFFE53935).withAlpha(102))
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Brand.royalBlue.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                // ✅ FIX-5: CachedNetworkImage instead of Image.network
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        height: 110,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                            child: _buildMachineIconFallback(
                                catalog?['category'], isDark)),
                        errorWidget: (_, __, ___) => Center(
                            child: _buildMachineIconFallback(
                                catalog?['category'], isDark)),
                      )
                    : Center(
                        child: _buildMachineIconFallback(
                            catalog?['category'], isDark)),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(status.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3)),
                  ]),
                ),
              ),
              if (warrantyDate != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: warrantyValid
                            ? (isDark
                                ? Brand.lightGreenBright
                                : Brand.lightGreen)
                            : (isDark ? const Color(0xFFFF6B6B) : Colors.red),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified_user_rounded,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(warrantyValid ? 'WARRANTY' : 'EXPIRED',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3)),
                    ]),
                  ),
                ),
              if (isFav)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      shape: BoxShape.circle,
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                  color: const Color(0xFFFF9800).withAlpha(77),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))
                            ],
                    ),
                    child: const Icon(Icons.star_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (catalog?['brand'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: isDark
                                ? Brand.darkIconActive.withAlpha(26)
                                : Brand.royalBlue.withAlpha(20),
                            borderRadius: BorderRadius.circular(5)),
                        child: Text(catalog!['brand'].toString(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue)),
                      ),
                    const SizedBox(height: 6),
                    Text(catalog?['machine_name'] ?? 'Unknown',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                            height: 1.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Row(children: [
                      Expanded(
                        child: Text('S/N: ${machine['serial_number'] ?? 'N/A'}',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isOverdue)
                        Icon(Icons.error_rounded,
                            size: 16,
                            color: isDark
                                ? const Color(0xFFFF6B6B)
                                : Colors.red.shade400),
                    ]),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMachineIconFallback(String? category, bool isDark) {
    return Center(
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: Brand.darkBorderLight) : null,
        ),
        child: Icon(_getCategoryIcon(category),
            size: 28,
            color: isDark
                ? Brand.darkIconActive.withAlpha(128)
                : Brand.royalBlue.withAlpha(77)),
      ),
    );
  }

  // ─── SORT BOTTOM SHEET ─────────────────────────────────────

  Widget _buildSortSheet(bool isDark) {
    final sortOptions = [
      {'key': 'recent', 'label': 'Most Recent', 'icon': Icons.schedule_rounded},
      {'key': 'name', 'label': 'Name (A-Z)', 'icon': Icons.sort_by_alpha},
      {
        'key': 'warranty',
        'label': 'Warranty Expiry',
        'icon': Icons.verified_user_rounded
      },
      {'key': 'status', 'label': 'Status', 'icon': Icons.flag_rounded},
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight.withAlpha(77),
                  borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(S.of(context)!.machineSortBy,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            const SizedBox(height: 16),
            ...sortOptions.map((option) {
              final isSelected = _sortBy == option['key'];
              return ListTile(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sortBy = option['key'] as String);
                  Navigator.pop(context);
                },
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                              ? Brand.darkIconActive.withAlpha(26)
                              : Brand.royalBlue.withAlpha(20))
                          : (isDark
                              ? Brand.darkCardElevated
                              : Brand.royalBlueSurface),
                      borderRadius: BorderRadius.circular(12),
                      border: isDark && isSelected
                          ? Border.all(
                              color: Brand.darkIconActive.withAlpha(51))
                          : null),
                  child: Icon(option['icon'] as IconData,
                      color: isSelected
                          ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                      size: 20),
                ),
                title: Text(option['label'] as String,
                    style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                            : (isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark))),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded,
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                        size: 22)
                    : null,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              );
            }),
            const SizedBox(height: 8),
          ]),
    );
  }

  // ─── MACHINE ACTIONS SHEET ─────────────────────────────────

  Widget _buildMachineActionsSheet(Map<String, dynamic> machine,
      Map<String, dynamic>? catalog, bool isDark) {
    final isFav = machine['is_favorite'] == true;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkTextTertiary
                  : Brand.subtleLight.withAlpha(77),
              borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(14),
                border:
                    isDark ? Border.all(color: Brand.darkBorderLight) : null),
            child: Icon(_getCategoryIcon(catalog?['category']),
                color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(catalog?['machine_name'] ?? 'Unknown',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(catalog?['brand']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.subtleLight)),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        _buildActionItem(
          icon: Icons.info_outline_rounded,
          label: S.of(context)!.machineViewDetails,
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _navigateToDetail(machine);
          },
        ),
        _buildActionItem(
          icon: isFav ? Icons.star_border_rounded : Icons.star_rounded,
          label: isFav
              ? S.of(context)!.machineRemoveFavorite
              : S.of(context)!.machineAddFavorite,
          color: const Color(0xFFFF9800),
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _toggleFavorite(machine);
          },
        ),
        _buildActionItem(
          iconWidget: IcChatGearIcon(
              color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
              size: 20),
          label: S.of(context)!.machineGetSupport,
          color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
          },
        ),
        _buildActionItem(
          icon: Icons.description_rounded,
          label: S.of(context)!.machineViewManual,
          color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF2196F3),
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildActionItem({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 26 : 20),
            borderRadius: BorderRadius.circular(12),
            border: isDark ? Border.all(color: color.withAlpha(31)) : null),
        child: iconWidget ?? Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          size: 16,
          color: isDark
              ? Brand.darkTextTertiary
              : Brand.subtleLight.withAlpha(102)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  // ─── SKELETON LOADING ──────────────────────────────────────

  Widget _buildSkeletonLoading(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(
          children: List.generate(
              4,
              (_) => Expanded(
                    child: Container(
                      height: 90,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: Brand.surface(isDark),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: isDark
                                  ? Brand.darkBorder
                                  : Brand.borderLight)),
                      child: _buildShimmer(isDark),
                    ),
                  )),
        ),
        const SizedBox(height: 20),
        ...List.generate(
            4,
            (_) => Container(
                  height: 100,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Brand.surface(isDark),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              isDark ? Brand.darkBorder : Brand.borderLight)),
                  child: _buildShimmer(isDark),
                )),
      ]),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return _ShimmerWidget(
        baseColor: isDark ? Brand.darkBorderLight : Brand.subtleLight);
  }

  // ─── ERROR STATE ───────────────────────────────────────────

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(22),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(10),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  color: Colors.red.withAlpha(isDark ? 31 : 15),
                  borderRadius: BorderRadius.circular(24),
                  border: isDark
                      ? Border.all(color: const Color(0xFFFF6B6B).withAlpha(38))
                      : null),
              child: Icon(Icons.cloud_off_rounded,
                  size: 42,
                  color:
                      isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400),
            ),
            const SizedBox(height: 20),
            Text(S.of(context)!.commonSomethingWentWrong,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            const SizedBox(height: 10),
            Text(
                S.of(context)!.machineLoadError,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadMachines,
                icon: const Icon(Icons.refresh_rounded, size: 22),
                label: Text(S.of(context)!.commonRetry,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Brand.darkIconActive : Brand.royalBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    final isFiltered = _filterStatus != 'all' || _searchQuery.isNotEmpty;
    final t = S.of(context)!;

    return SingleChildScrollView(
      child: DsEmptyState(
        icon: isFiltered
            ? Icons.search_off_rounded
            : Icons.precision_manufacturing_rounded,
        title: isFiltered ? t.machineNoMachinesFound : t.machineNoMachines,
        subtitle: isFiltered ? t.machineNoMatchDesc : t.machineRegisterDesc,
        action: ElevatedButton.icon(
          onPressed: isFiltered
              ? () {
                  setState(() {
                    _filterStatus = 'all';
                    _searchQuery = '';
                    _searchController.clear();
                  });
                }
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterMachinePage()),
                  ).then((_) {
                    if (mounted) _loadMachines();
                  });
                },
          icon: Icon(
              isFiltered ? Icons.clear_all_rounded : Icons.add_rounded,
              size: 20),
          label: Text(
              isFiltered ? t.machineClearFilters : t.machineRegisterFirst,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ─── FAB ───────────────────────────────────────────────────

  Widget _buildFAB(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkIconActive, Brand.royalBlueGlow]
              : [Brand.royalBlue, Brand.royalBlueLight],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Brand.darkIconActive.withAlpha(77)
                  : Brand.royalBlue.withAlpha(102),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterMachinePage()),
          ).then((_) {
            if (mounted) _loadMachines();
          });
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
        label: Text(S.of(context)!.machineRegister,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
  }
}

// ─── SHIMMER WIDGET ──────────────────────────────────────────

class _ShimmerWidget extends StatefulWidget {
  final Color baseColor;
  const _ShimmerWidget({required this.baseColor});

  @override
  State<_ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<_ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * value, 0),
              end: Alignment(-1 + 2 * value + 1, 0),
              colors: [
                widget.baseColor.withAlpha(13),
                widget.baseColor.withAlpha(31),
                widget.baseColor.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
        );
      },
    );
  }
}
