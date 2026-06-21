import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import 'ea_leave_detail_page.dart';

const Color _eaAccent = Brand.lightGreenDark;

class EaLeaveManagementPage extends StatefulWidget {
  final String? engineerId;
  final String? engineerName;

  const EaLeaveManagementPage({
    super.key,
    this.engineerId,
    this.engineerName,
  });

  @override
  State<EaLeaveManagementPage> createState() => _EaLeaveManagementPageState();
}

class _EaLeaveManagementPageState extends State<EaLeaveManagementPage> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  String _statusFilter = 'all';
  String _sortBy = 'date_desc';
  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  static const _statuses = ['all', 'pending', 'approved', 'rejected', 'cancelled'];

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
      var q = SupabaseConfig.client
          .from('engineer_leaves')
          .select('*, engineer:users!engineer_id(id, full_name, profile_photo, employee_id, assigned_zone)');

      if (widget.engineerId != null) {
        q = q.eq('engineer_id', widget.engineerId!);
      }

      final data = await q.order('start_date', ascending: false);

      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(data);
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
    List<Map<String, dynamic>> list = List.from(_all);

    // Status filter
    if (_statusFilter != 'all') {
      list = list.where((r) => r['status'] == _statusFilter).toList();
    }

    // Search
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final eng = r['engineer'] as Map? ?? {};
        final name = (eng['full_name'] ?? '').toString().toLowerCase();
        final type = (r['leave_type'] ?? '').toString().toLowerCase();
        final reason = (r['reason'] ?? '').toString().toLowerCase();
        return name.contains(q) || type.contains(q) || reason.contains(q);
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      switch (_sortBy) {
        case 'date_asc':
          return (a['start_date'] ?? '').toString().compareTo((b['start_date'] ?? '').toString());
        case 'engineer':
          final aName = ((a['engineer'] as Map?)?['full_name'] ?? '').toString();
          final bName = ((b['engineer'] as Map?)?['full_name'] ?? '').toString();
          return aName.compareTo(bName);
        case 'duration':
          final aDays = (a['total_days'] as num?)?.toDouble() ?? 0;
          final bDays = (b['total_days'] as num?)?.toDouble() ?? 0;
          return bDays.compareTo(aDays);
        default: // date_desc
          return (b['start_date'] ?? '').toString().compareTo((a['start_date'] ?? '').toString());
      }
    });

    setState(() => _filtered = list);
  }

  void _onSearch(String v) {
    _searchQuery = v;
    _applyFilter();
  }

  Future<void> _quickApprove(Map<String, dynamic> leave) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Leave'),
        content: const Text('Approve this leave application?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: StatusColors.resolved),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SupabaseConfig.client
          .from('engineer_leaves')
          .update({
            'status': 'approved',
            'reviewed_by': SupabaseConfig.client.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', leave['id']);
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave approved'), backgroundColor: StatusColors.resolved),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.error),
      );
    }
  }

  Future<void> _quickReject(Map<String, dynamic> leave) async {
    final noteCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reject this leave application?'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Rejection reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.error),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirm != true || !mounted) return;
    try {
      await SupabaseConfig.client
          .from('engineer_leaves')
          .update({
            'status': 'rejected',
            'reviewed_by': SupabaseConfig.client.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            if (note.isNotEmpty) 'review_note': note,
          })
          .eq('id', leave['id']);
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave rejected'), backgroundColor: AdminColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.error),
      );
    }
  }

  void _showSortSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
      ),
      builder: (_) {
        const opts = [
          ('date_desc', 'Newest First'),
          ('date_asc', 'Oldest First'),
          ('engineer', 'Engineer Name'),
          ('duration', 'Duration (Longest)'),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sort By',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.text(context),
                  )),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: _sortBy,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _sortBy = v);
                  _applyFilter();
                  Navigator.pop(context);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: opts
                      .map((opt) => RadioListTile<String>(
                            value: opt.$1,
                            title: Text(opt.$2),
                            activeColor: _eaAccent,
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── counts ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: Column(children: [
        DsPageHeader(
          accent: HeroAccent.emerald,
          title: widget.engineerName != null
              ? '${widget.engineerName}\'s Leaves'
              : 'Leave Management',
          actions: [
            DsHeroAction(Icons.sort_rounded, _showSortSheet, tooltip: 'Sort'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
        onRefresh: _load,
        color: _eaAccent,
        child: CustomScrollView(
          slivers: [
            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: 'Search engineer, type, reason…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),

            // Summary row
            if (!_loading && _error == null)
              SliverToBoxAdapter(child: _SummaryRow(all: _all)),

            // Status filter chips
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: _statuses.map((s) {
                    final selected = _statusFilter == s;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_statusLabel(s)),
                        selected: selected,
                        selectedColor: _eaAccent.withAlpha(30),
                        checkmarkColor: _eaAccent,
                        labelStyle: TextStyle(
                          color: selected ? _eaAccent : AdminColors.textSub(context),
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color: selected ? _eaAccent : AdminColors.border(context),
                        ),
                        onSelected: (_) {
                          setState(() => _statusFilter = s);
                          _applyFilter();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Content
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(child: _ErrorView(message: _error!, onRetry: _load))
            else if (_filtered.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(
                  statusFilter: _statusFilter,
                  searchQuery: _searchQuery,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _LeaveCard(
                      leave: _filtered[i],
                      onTap: () async {
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EaLeaveDetailPage(leaveId: _filtered[i]['id'] as String),
                          ),
                        );
                        if (result == true) _load();
                      },
                      onApprove: _filtered[i]['status'] == 'pending'
                          ? () => _quickApprove(_filtered[i])
                          : null,
                      onReject: _filtered[i]['status'] == 'pending'
                          ? () => _quickReject(_filtered[i])
                          : null,
                    ),
                    childCount: _filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
        ),
      ]),
    );
  }
}

// ── label helpers ─────────────────────────────────────────────────────────────

String _statusLabel(String s) {
  switch (s) {
    case 'pending': return 'Pending';
    case 'approved': return 'Approved';
    case 'rejected': return 'Rejected';
    case 'cancelled': return 'Cancelled';
    default: return 'All';
  }
}

Color _statusColor(String? s) {
  switch (s) {
    case 'pending': return AdminColors.warning;
    case 'approved': return StatusColors.resolved;
    case 'rejected': return AdminColors.error;
    case 'cancelled': return Brand.subtleLight;
    default: return Brand.subtleLight;
  }
}

Color _leaveTypeColor(String? t) {
  switch (t) {
    case 'sick': return AdminColors.error;
    case 'casual': return AdminColors.info;
    case 'annual': return StatusColors.resolved;
    case 'emergency': return AdminColors.error;
    case 'maternity': return StatusColors.pink;
    case 'paternity': return StatusColors.assigned;
    default: return Brand.subtleLight;
  }
}

String _leaveTypeLabel(String? t) {
  switch (t) {
    case 'sick': return 'Sick Leave';
    case 'casual': return 'Casual Leave';
    case 'annual': return 'Annual Leave';
    case 'emergency': return 'Emergency Leave';
    case 'maternity': return 'Maternity Leave';
    case 'paternity': return 'Paternity Leave';
    default: return (t ?? 'Leave');
  }
}

// ── Summary Row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final List<Map<String, dynamic>> all;
  const _SummaryRow({required this.all});

  int _count(String s) => all.where((r) => r['status'] == s).length;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _SummaryChip(label: 'Total', count: all.length, color: _eaAccent),
          const SizedBox(width: 8),
          _SummaryChip(label: 'Pending', count: _count('pending'), color: AdminColors.warning),
          const SizedBox(width: 8),
          _SummaryChip(label: 'Approved', count: _count('approved'), color: StatusColors.resolved),
          const SizedBox(width: 8),
          _SummaryChip(label: 'Rejected', count: _count('rejected'), color: AdminColors.error),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withAlpha(200)),
          ),
        ],
      ),
    );
  }
}

// ── Leave Card ────────────────────────────────────────────────────────────────

class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> leave;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _LeaveCard({
    required this.leave,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eng = leave['engineer'] as Map<String, dynamic>? ?? {};
    final status = leave['status'] as String? ?? 'pending';
    final leaveType = leave['leave_type'] as String?;
    final startDate = leave['start_date'] as String?;
    final endDate = leave['end_date'] as String?;
    final durationDays = (leave['total_days'] as num?)?.toDouble() ?? 1.0;
    final reason = leave['reason'] as String?;
    final typeColor = _leaveTypeColor(leaveType);
    final statusColor = _statusColor(status);

    String dateRange = '';
    if (startDate != null) {
      final fmt = DateFormat('d MMM');
      final s = fmt.format(DateTime.tryParse(startDate) ?? DateTime.now());
      if (endDate != null && endDate != startDate) {
        final e = fmt.format(DateTime.tryParse(endDate) ?? DateTime.now());
        dateRange = '$s – $e';
      } else {
        dateRange = s;
      }
    }

    final photoUrl = eng['profile_photo'] as String?;
    final name = eng['full_name'] as String? ?? 'Engineer';
    final zone = eng['assigned_zone'] as String?;
    final empId = eng['employee_id'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(color: AdminColors.border(context)),
          boxShadow: isDark
              ? []
              : [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: leave type badge + status + date
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                      border: Border.all(color: typeColor.withAlpha(60)),
                    ),
                    child: Text(
                      _leaveTypeLabel(leaveType),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: typeColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Engineer info
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _avatar(photoUrl, name, 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AdminColors.text(context),
                            )),
                        if (zone != null || empId != null)
                          Text(
                            [if (empId != null) '#$empId', if (zone != null) zone].join(' · '),
                            style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$durationDays ${durationDays == 1 ? 'day' : 'days'}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                      if (dateRange.isNotEmpty)
                        Text(dateRange,
                            style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
                    ],
                  ),
                ],
              ),
            ),

            // Reason
            if (reason != null && reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(
                  reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AdminColors.textSub(context)),
                ),
              ),

            // Approve / Reject quick actions (pending only)
            if (onApprove != null || onReject != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    if (onReject != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onReject,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminColors.error,
                            side: const BorderSide(color: AdminColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (onApprove != null && onReject != null) const SizedBox(width: 10),
                    if (onApprove != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StatusColors.resolved,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            elevation: 0,
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),

            // Tap hint
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('View details',
                      style: TextStyle(fontSize: 11, color: _eaAccent.withAlpha(180))),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 14, color: _eaAccent.withAlpha(180)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String? url, String name, double size) {
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallbackAvatar(name, size),
          errorWidget: (_, __, ___) => _fallbackAvatar(name, size),
        ),
      );
    }
    return _fallbackAvatar(name, size);
  }

  Widget _fallbackAvatar(String name, double size) {
    final initials = name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _eaAccent.withAlpha(40),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.bold, color: _eaAccent)),
    );
  }
}

// ── Error / Empty ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AdminColors.error.withAlpha(180)),
            const SizedBox(height: 12),
            Text('Failed to load leaves', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.text(context))),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AdminColors.textSub(context))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: _eaAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String statusFilter;
  final String searchQuery;
  const _EmptyState({required this.statusFilter, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final msg = searchQuery.isNotEmpty
        ? 'No leaves match "$searchQuery"'
        : statusFilter != 'all'
            ? 'No ${_statusLabel(statusFilter).toLowerCase()} leave applications'
            : 'No leave applications found';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.beach_access_rounded, size: 56, color: AdminColors.textHint(context)),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: AdminColors.textSub(context), fontSize: 14)),
        ],
      ),
    );
  }
}
