// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_job_records_page.dart
// Engineering Admin Portal — Screen 8: Job Records
// Lists all job_records with filters, search, and navigation to
// detail page. Supports creating new records via FAB.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import 'ea_job_record_detail_page.dart';
import 'ea_job_record_form_page.dart';

const Color _eaAccent = Brand.lightGreenDark;

class EaJobRecordsPage extends StatefulWidget {
  // Optional: pre-filter by a specific engineer
  final String? engineerId;
  final String? engineerName;

  const EaJobRecordsPage({
    super.key,
    this.engineerId,
    this.engineerName,
  });

  @override
  State<EaJobRecordsPage> createState() => _EaJobRecordsPageState();
}

class _EaJobRecordsPageState extends State<EaJobRecordsPage> {
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  String _statusFilter = 'all'; // all | pending | in_progress | completed | cancelled
  String _sortBy = 'date_desc'; // date_desc | date_asc | engineer | duration

  static const _statuses = [
    'all',
    'pending',
    'in_progress',
    'completed',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = SupabaseConfig.client
          .from('job_records')
          .select('''
            *,
            engineer:users!engineer_id(id, full_name, profile_photo, employee_id, assigned_zone),
            ticket:service_tickets!ticket_id(id, ticket_number, subject, status)
          ''');

      if (widget.engineerId != null) {
        query = query.eq('engineer_id', widget.engineerId!);
      }

      final data = await query.order('job_date', ascending: false);

      if (!mounted) return;
      setState(() {
        _all = (data as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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
    final q = _searchCtrl.text.trim().toLowerCase();

    var list = _all.where((r) {
      // Status filter
      if (_statusFilter != 'all' && r['status'] != _statusFilter) return false;

      // Search
      if (q.isNotEmpty) {
        final eng = r['engineer'] as Map<String, dynamic>?;
        final ticket = r['ticket'] as Map<String, dynamic>?;
        final engName = (eng?['full_name'] as String? ?? '').toLowerCase();
        final ticketTitle = (ticket?['subject'] as String? ?? '').toLowerCase();
        final ticketNum = (ticket?['ticket_number'] as String? ?? '').toLowerCase();
        final jobType = (r['job_type'] as String? ?? '').toLowerCase();
        if (!engName.contains(q) &&
            !ticketTitle.contains(q) &&
            !ticketNum.contains(q) &&
            !jobType.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sort
    switch (_sortBy) {
      case 'date_asc':
        list.sort((a, b) =>
            (a['job_date'] as String? ?? '').compareTo(b['job_date'] as String? ?? ''));
      case 'date_desc':
        list.sort((a, b) =>
            (b['job_date'] as String? ?? '').compareTo(a['job_date'] as String? ?? ''));
      case 'engineer':
        list.sort((a, b) {
          final aName = ((a['engineer'] as Map?)?.get('full_name') ?? '') as String;
          final bName = ((b['engineer'] as Map?)?.get('full_name') ?? '') as String;
          return aName.compareTo(bName);
        });
      case 'duration':
        list.sort((a, b) =>
            ((b['duration_hours'] as num?) ?? 0)
                .compareTo((a['duration_hours'] as num?) ?? 0));
    }

    setState(() => _filtered = list);
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return AdminColors.warning;
      case 'in_progress':
        return AdminColors.info;
      case 'completed':
        return StatusColors.resolved;
      case 'cancelled':
        return AdminColors.error;
      default:
        return Brand.subtleLight;
    }
  }

  String _jobTypeLabel(String? t) {
    switch (t) {
      case 'installation':
        return 'Installation';
      case 'repair':
        return 'Repair';
      case 'maintenance':
        return 'Maintenance';
      case 'inspection':
        return 'Inspection';
      case 'warranty':
        return 'Warranty Visit';
      default:
        return t ?? 'Job';
    }
  }

  IconData _jobTypeIcon(String? t) {
    switch (t) {
      case 'installation':
        return Icons.build_rounded;
      case 'repair':
        return Icons.handyman_rounded;
      case 'maintenance':
        return Icons.settings_rounded;
      case 'inspection':
        return Icons.search_rounded;
      case 'warranty':
        return Icons.verified_rounded;
      default:
        return Icons.work_rounded;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr);
      final months = [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  // ── Sort sheet ────────────────────────────────────────────────

  void _showSortSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : Brand.darkSurface;
    final textSecondary = isDark ? Brand.darkTextSecondary : AdminColors.textSecondaryLight;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(Brand.r(2)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Sort by',
                style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 12),
            for (final opt in [
              ('date_desc', 'Date (Newest first)', Icons.arrow_downward_rounded),
              ('date_asc', 'Date (Oldest first)', Icons.arrow_upward_rounded),
              ('engineer', 'Engineer name', Icons.person_rounded),
              ('duration', 'Duration (Longest first)', Icons.timer_rounded),
            ])
              ListTile(
                leading: Icon(opt.$3,
                    color:
                        _sortBy == opt.$1 ? _eaAccent : textSecondary,
                    size: 20),
                title: Text(opt.$2,
                    style: TextStyle(
                        color: _sortBy == opt.$1 ? _eaAccent : textPrimary,
                        fontWeight: _sortBy == opt.$1
                            ? FontWeight.w700
                            : FontWeight.w500)),
                trailing: _sortBy == opt.$1
                    ? const Icon(Icons.check_rounded, color: _eaAccent)
                    : null,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
                onTap: () {
                  setState(() => _sortBy = opt.$1);
                  _applyFilter();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Brand.canvas(isDark);
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : Brand.darkSurface;
    final textSecondary = isDark ? Brand.darkTextSecondary : AdminColors.textSecondaryLight;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => EaJobRecordFormPage(
                preselectedEngineerId: widget.engineerId,
                preselectedEngineerName: widget.engineerName,
              ),
            ),
          );
          if (created == true) _load();
        },
        backgroundColor: _eaAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Record',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          DsPageHeader(
            accent: HeroAccent.emerald,
            title: widget.engineerName != null
                ? "${widget.engineerName}'s Jobs"
                : "Job Records",
            actions: [
              DsHeroAction(Icons.sort_rounded, _showSortSheet, tooltip: "Sort"),
            ],
          ),
          // ── Search + status filter ─────────────────────────────
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by engineer, ticket, type…',
                    hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: textSecondary, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
                            icon: Icon(Icons.close_rounded,
                                color: textSecondary, size: 18),
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Status filter tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statuses.map((s) {
                      final sel = _statusFilter == s;
                      final col = s == 'all' ? _eaAccent : _statusColor(s);
                      final label = s == 'all' ? 'All' : _statusLabel(s);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _statusFilter = s);
                            _applyFilter();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? col.withAlpha(25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(Brand.r(20)),
                              border: Border.all(
                                color: sel ? col : borderColor,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: sel ? col : textSecondary,
                                fontSize: 12,
                                fontWeight: sel
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── Count bar ──────────────────────────────────────────
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} record${_filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Sorted: ${_sortLabel(_sortBy)}',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // ── Content ────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _eaAccent))
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? _EmptyState(
                            hasSearch: _searchCtrl.text.isNotEmpty ||
                                _statusFilter != 'all',
                          )
                        : RefreshIndicator(
                            color: _eaAccent,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 16, 100),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final r = _filtered[i];
                                return _JobRecordCard(
                                  record: r,
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  statusColor:
                                      _statusColor(r['status'] as String? ?? ''),
                                  statusLabel:
                                      _statusLabel(r['status'] as String? ?? ''),
                                  jobTypeLabel:
                                      _jobTypeLabel(r['job_type'] as String?),
                                  jobTypeIcon:
                                      _jobTypeIcon(r['job_type'] as String?),
                                  dateLabel: _formatDate(r['job_date'] as String?),
                                  onTap: () async {
                                    final changed =
                                        await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EaJobRecordDetailPage(
                                          recordId: r['id'] as String,
                                        ),
                                      ),
                                    );
                                    if (changed == true) _load();
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(String s) {
    switch (s) {
      case 'date_desc':
        return 'Newest first';
      case 'date_asc':
        return 'Oldest first';
      case 'engineer':
        return 'Engineer';
      case 'duration':
        return 'Duration';
      default:
        return s;
    }
  }
}

// ── Job Record Card ───────────────────────────────────────────────────────────

class _JobRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color statusColor;
  final String statusLabel;
  final String jobTypeLabel;
  final IconData jobTypeIcon;
  final String dateLabel;
  final VoidCallback onTap;

  const _JobRecordCard({
    required this.record,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.statusColor,
    required this.statusLabel,
    required this.jobTypeLabel,
    required this.jobTypeIcon,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;
    final eng = record['engineer'] as Map<String, dynamic>?;
    final ticket = record['ticket'] as Map<String, dynamic>?;
    final duration = (record['duration_hours'] as num?)?.toDouble();
    final photoUrl = eng?['profile_photo'] as String?;
    final engName = eng?['full_name'] as String? ?? 'Unknown';
    final empId = eng?['employee_id'] as String? ?? '';
    final ticketNum = ticket?['ticket_number'] as String? ?? '';
    final ticketTitle = ticket?['subject'] as String? ?? '';

    final initials = engName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: job type + status + date ─────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _eaAccent.withAlpha(isDark ? 30 : 20),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                      ),
                      child: Icon(jobTypeIcon, size: 18, color: _eaAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            jobTypeLabel,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            dateLabel,
                            style:
                                TextStyle(color: textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(Brand.r(8)),
                        border: Border.all(color: statusColor.withAlpha(60)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Row 2: engineer avatar + name ────────────────
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _eaAccent.withAlpha(60), width: 1.5),
                      ),
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => _MiniAvatar(
                                    initials: initials, isDark: isDark),
                                errorWidget: (_, __, ___) => _MiniAvatar(
                                    initials: initials, isDark: isDark),
                              )
                            : _MiniAvatar(initials: initials, isDark: isDark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        empId.isNotEmpty ? '$engName · $empId' : engName,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (duration != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_rounded,
                              size: 13, color: textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            '${duration.toStringAsFixed(1)}h',
                            style: TextStyle(
                                color: textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),

                // ── Ticket reference ─────────────────────────────
                if (ticketNum.isNotEmpty || ticketTitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.confirmation_number_outlined,
                            size: 13, color: Brand.royalBlue),
                        const SizedBox(width: 6),
                        if (ticketNum.isNotEmpty)
                          Text(
                            '#$ticketNum ',
                            style: TextStyle(
                              color: Brand.royalBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            ticketTitle,
                            style: TextStyle(
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.royalBlue,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String initials;
  final bool isDark;

  const _MiniAvatar({required this.initials, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Brand.royalBlue,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ── Error / Empty ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load job records',
              style: TextStyle(
                color: isDark ? Brand.darkTextPrimary : Brand.darkSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: Brand.subtleLight, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasSearch;

  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch
                ? Icons.search_off_rounded
                : Icons.work_outline_rounded,
            size: 64,
            color: isDark ? Brand.darkTextTertiary : Brand.borderMedium,
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No records match your filters' : 'No job records yet',
            style: TextStyle(
              color: isDark ? Brand.darkTextSecondary : AdminColors.textSecondaryLight,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 8),
            Text(
              'Tap + to create the first record',
              style: TextStyle(
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Extension helper ──────────────────────────────────────────────────────────

extension _MapGet on Map {
  dynamic get(String key) => this[key];
}
