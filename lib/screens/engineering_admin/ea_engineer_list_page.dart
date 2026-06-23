// lib/screens/engineering_admin/ea_engineer_list_page.dart
// Engineering Admin Portal â€” Screen 5: Engineer List
// v20 â€” Phase 1

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../repositories/engineering_admin_repository.dart';
import '../../utils/time_utils.dart';
import 'ea_engineer_detail_page.dart';
import 'ea_create_engineer_page.dart';

const Color _eaAccent = Color(0xFF16A34A);

// Sort options
enum _SortBy { name, zone, rating, joinDate }

class EaEngineerListPage extends StatefulWidget {
  const EaEngineerListPage({super.key});

  @override
  State<EaEngineerListPage> createState() => _EaEngineerListPageState();
}

class _EaEngineerListPageState extends State<EaEngineerListPage> {
  final _repo = EngineeringAdminRepository();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _engineers = [];
  bool _loading = true;
  String? _error;

  String _search = '';
  String? _zoneFilter;
  String? _empTypeFilter;
  String? _statusFilter; // present / absent / on_leave / all
  _SortBy _sortBy = _SortBy.name;

  static const _zones = ['North', 'South', 'East', 'West', 'Central'];
  static const _empTypes = ['full_time', 'part_time', 'contract'];
  static const _statuses = ['present', 'absent', 'on_leave'];

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
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getEngineerList(
        search: null, // client-side filtering
        zone: _zoneFilter,
        employmentType: _empTypeFilter,
      );
      if (!mounted) return;
      setState(() {
        _engineers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_engineers);

    // Search filter
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((e) {
        final name = (e['full_name'] ?? '').toString().toLowerCase();
        final empId = (e['employee_id'] ?? '').toString().toLowerCase();
        final zone = (e['assigned_zone'] ?? '').toString().toLowerCase();
        return name.contains(q) || empId.contains(q) || zone.contains(q);
      }).toList();
    }

    // Status filter
    if (_statusFilter != null && _statusFilter != 'all') {
      list = list.where((e) {
        final att = e['attendance_status'] as String?;
        if (_statusFilter == 'present') {
          return att == 'present' || att == 'late' || att == 'half_day';
        } else if (_statusFilter == 'on_leave') {
          return att == 'on_leave';
        } else {
          // absent
          return att == null || att == 'absent';
        }
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      switch (_sortBy) {
        case _SortBy.name:
          return (a['full_name'] ?? '').toString().compareTo(
                (b['full_name'] ?? '').toString(),
              );
        case _SortBy.zone:
          return (a['assigned_zone'] ?? '').toString().compareTo(
                (b['assigned_zone'] ?? '').toString(),
              );
        case _SortBy.rating:
          final ra = (a['avg_rating'] as num?)?.toDouble() ?? 0.0;
          final rb = (b['avg_rating'] as num?)?.toDouble() ?? 0.0;
          return rb.compareTo(ra); // desc
        case _SortBy.joinDate:
          final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
          return db.compareTo(da); // newest first
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: Column(
        children: [
          DsPageHeader(
            accent: HeroAccent.emerald,
            title: 'Engineer Team',
            showBack: false,
            actions: [
              DsHeroAction(Icons.sort_rounded, () => _showSortSheet(isDark)),
              const SizedBox(width: 6),
              DsHeroAction(Icons.refresh_rounded, _load),
            ],
          ),
          // â”€â”€ Search + Filters â”€â”€
          Container(
            color: Brand.surface(isDark),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name, ID or zoneâ€¦',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor:
                        isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                // Filter chips row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChipDropdown(
                        label: _zoneFilter ?? 'Zone',
                        isActive: _zoneFilter != null,
                        isDark: isDark,
                        onTap: () => _showZonePicker(isDark),
                      ),
                      const SizedBox(width: 8),
                      _filterChipDropdown(
                        label: _empTypeFilter != null
                            ? _empTypeLabel(_empTypeFilter!)
                            : 'Type',
                        isActive: _empTypeFilter != null,
                        isDark: isDark,
                        onTap: () => _showEmpTypePicker(isDark),
                      ),
                      const SizedBox(width: 8),
                      _filterChipDropdown(
                        label: _statusFilter != null && _statusFilter != 'all'
                            ? _statusLabel(_statusFilter!)
                            : 'Status',
                        isActive: _statusFilter != null &&
                            _statusFilter != 'all',
                        isDark: isDark,
                        onTap: () => _showStatusPicker(isDark),
                      ),
                      if (_zoneFilter != null ||
                          _empTypeFilter != null ||
                          (_statusFilter != null &&
                              _statusFilter != 'all')) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _clearFilters,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AdminColors.error.withAlpha(20),
                              borderRadius: BorderRadius.circular(Brand.r(20)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.clear_rounded,
                                    size: 14, color: AdminColors.error),
                                const SizedBox(width: 4),
                                Text(
                                  'Clear',
                                  style: TextStyle(
                                    fontSize: 11,
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
                ),
              ],
            ),
          ),

          // â”€â”€ Count + Sort label â”€â”€
          if (!_loading && _error == null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} engineer${filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textHint(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Sort: ${_sortLabel(_sortBy)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textHint(context),
                    ),
                  ),
                ],
              ),
            ),

          // â”€â”€ List â”€â”€
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _eaAccent))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: StatusColors.danger),
                            const SizedBox(height: 12),
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _load,
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _eaAccent,
                        child: filtered.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.engineering_rounded,
                                          size: 56,
                                          color: AdminColors.textHint(context),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No engineers found',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Brand.darkTextPrimary
                                                : Brand.royalBlueDark,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Try adjusting the filters',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                AdminColors.textHint(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 100),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) =>
                                    _buildEngineerCard(filtered[i], isDark),
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _inviteEngineer,
        backgroundColor: _eaAccent,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'Add Engineer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // â”€â”€ Engineer Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildEngineerCard(Map<String, dynamic> eng, bool isDark) {
    final name = eng['full_name'] as String? ?? 'Unknown';
    final empId = eng['employee_id'] as String? ?? '';
    final zone = eng['assigned_zone'] as String? ?? 'N/A';
    final photoUrl = eng['profile_photo'] as String?;
    final empType = eng['employment_type'] as String? ?? '';
    final attStatus = eng['attendance_status'] as String?;
    final activeJobs = eng['active_jobs'] as int? ?? 0;
    final rating = (eng['avg_rating'] as num?)?.toDouble();
    final checkInTime = eng['check_in_time'] as String?;

    final statusColor = _attendanceColor(attStatus);
    final statusLabel = _attendanceLabel(attStatus);

    return InkWell(
      onTap: () => _openEngineerDetail(eng),
      borderRadius: BorderRadius.circular(Brand.r(16)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            // â”€â”€ Avatar with status ring â”€â”€
            Stack(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 2.5),
                  ),
                  child: ClipOval(
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _avatarFallback(name, isDark),
                            errorWidget: (_, __, ___) =>
                                _avatarFallback(name, isDark),
                          )
                        : _avatarFallback(name, isDark),
                  ),
                ),
                // Active job count bubble
                if (activeJobs > 0)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _eaAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Brand.surface(isDark),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$activeJobs',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // â”€â”€ Info â”€â”€
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + rating
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                        ),
                      ),
                      if (rating != null) ...[
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Employee ID + zone
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (empId.isNotEmpty) ...[
                        Text(
                          empId,
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                        Text(
                          ' Â· ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                      ],
                      Icon(Icons.location_on_rounded,
                          size: 12,
                          color: AdminColors.textHint(context)),
                      const SizedBox(width: 2),
                      Text(
                        zone,
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Chips row: employment type + attendance status
                  Row(
                    children: [
                      if (empType.isNotEmpty)
                        _chip(
                          _empTypeLabel(empType),
                          isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                          AdminColors.textSub(context),
                          isDark,
                        ),
                      const SizedBox(width: 6),
                      _chip(
                        statusLabel,
                        statusColor.withAlpha(isDark ? 35 : 22),
                        statusColor,
                        isDark,
                        border: statusColor.withAlpha(60),
                      ),
                      if (checkInTime != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Â· in ${TimeUtils.formatTime(DateTime.tryParse(checkInTime) ?? DateTime.now())}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // â”€â”€ Chevron â”€â”€
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AdminColors.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Helper Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _avatarFallback(String name, bool isDark) {
    final initials = name.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return Container(
      color: _eaAccent.withAlpha(isDark ? 40 : 25),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _eaAccent,
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color textColor, bool isDark,
      {Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Brand.r(6)),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _filterChipDropdown({
    required String label,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? _eaAccent.withAlpha(isDark ? 40 : 20)
              : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: isActive
                ? _eaAccent.withAlpha(isDark ? 80 : 60)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? _eaAccent : AdminColors.textHint(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: isActive ? _eaAccent : AdminColors.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Bottom sheet pickers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showSortSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                    borderRadius: BorderRadius.circular(Brand.r(2)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color:
                      isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 12),
              ..._SortBy.values.map((s) {
                final selected = _sortBy == s;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _sortLabel(s),
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? _eaAccent
                          : (isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark),
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: _eaAccent)
                      : null,
                  onTap: () {
                    setState(() => _sortBy = s);
                    Navigator.pop(sheetCtx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showZonePicker(bool isDark) {
    _showPickerSheet(
      isDark: isDark,
      title: 'Filter by Zone',
      options: _zones,
      selectedValue: _zoneFilter,
      labelFor: (z) => z,
      onSelect: (z) => setState(() {
        _zoneFilter = z == _zoneFilter ? null : z;
      }),
    );
  }

  void _showEmpTypePicker(bool isDark) {
    _showPickerSheet(
      isDark: isDark,
      title: 'Employment Type',
      options: _empTypes,
      selectedValue: _empTypeFilter,
      labelFor: _empTypeLabel,
      onSelect: (t) => setState(() {
        _empTypeFilter = t == _empTypeFilter ? null : t;
      }),
    );
  }

  void _showStatusPicker(bool isDark) {
    _showPickerSheet(
      isDark: isDark,
      title: 'Filter by Status',
      options: _statuses,
      selectedValue: _statusFilter,
      labelFor: _statusLabel,
      onSelect: (s) => setState(() {
        _statusFilter = s == _statusFilter ? null : s;
      }),
    );
  }

  void _showPickerSheet({
    required bool isDark,
    required String title,
    required List<String> options,
    required String? selectedValue,
    required String Function(String) labelFor,
    required void Function(String) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                    borderRadius: BorderRadius.circular(Brand.r(2)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color:
                      isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap again to deselect',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textHint(context),
                ),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final selected = selectedValue == opt;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    labelFor(opt),
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? _eaAccent
                          : (isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark),
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: _eaAccent)
                      : null,
                  onTap: () {
                    onSelect(opt);
                    Navigator.pop(sheetCtx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // â”€â”€ Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _clearFilters() {
    setState(() {
      _zoneFilter = null;
      _empTypeFilter = null;
      _statusFilter = null;
    });
    _load();
  }

  void _openEngineerDetail(Map<String, dynamic> eng) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EaEngineerDetailPage(
          engineerId: eng['id'] as String? ?? '',
          engineerName: eng['full_name'] as String? ?? 'Engineer',
        ),
      ),
    );
  }

  Future<void> _inviteEngineer() async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EaCreateEngineerPage()),
    );
    if (refreshed == true) _load();
  }

  // â”€â”€ Label helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Color _attendanceColor(String? status) {
    switch (status) {
      case 'present':
        return AdminColors.success;
      case 'late':
        return AdminColors.warning;
      case 'half_day':
        return const Color(0xFF10B981);
      case 'on_leave':
        return AdminColors.info;
      case 'absent':
        return AdminColors.error;
      default:
        return AdminColors.error;
    }
  }

  String _attendanceLabel(String? status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'half_day':
        return 'Half Day';
      case 'on_leave':
        return 'On Leave';
      case 'absent':
        return 'Absent';
      default:
        return 'Not Checked In';
    }
  }

  String _empTypeLabel(String type) {
    switch (type) {
      case 'full_time':
        return 'Full Time';
      case 'part_time':
        return 'Part Time';
      case 'contract':
        return 'Contract';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'on_leave':
        return 'On Leave';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String _sortLabel(_SortBy s) {
    switch (s) {
      case _SortBy.name:
        return 'Name';
      case _SortBy.zone:
        return 'Zone';
      case _SortBy.rating:
        return 'Rating';
      case _SortBy.joinDate:
        return 'Join Date';
    }
  }
}