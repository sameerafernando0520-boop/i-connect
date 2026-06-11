// ============================================================
// lib/widgets/admin/assign_engineer_sheet.dart
// Reusable bottom sheet — admin picks an engineer for a ticket
// ============================================================

import 'package:flutter/material.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';

// ── Status Indicator Colors ──────────────────────────────
const _availableColor = Color(0xFF2EA043);
const _busyColor = Color(0xFFD29922);
const _offlineColor = Color(0xFF6E7681);

class AssignEngineerSheet extends StatefulWidget {
  final String ticketId;
  final String? currentEngineerId;

  const AssignEngineerSheet({
    super.key,
    required this.ticketId,
    this.currentEngineerId,
  });

  /// Call this from anywhere to show the sheet.
  /// Returns `true` if an engineer was assigned, `null` if dismissed.
  static Future<bool?> show(
    BuildContext context, {
    required String ticketId,
    String? currentEngineerId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssignEngineerSheet(
        ticketId: ticketId,
        currentEngineerId: currentEngineerId,
      ),
    );
  }

  @override
  State<AssignEngineerSheet> createState() => _AssignEngineerSheetState();
}

class _AssignEngineerSheetState extends State<AssignEngineerSheet> {
  final _supabase = SupabaseConfig.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _engineers = [];
  Map<String, int> _activeCounts = {};
  bool _isLoading = true;
  bool _isAssigning = false;
  String _search = '';

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

  // ── Data ─────────────────────────────────────────────────
  Future<void> _load() async {
    try {
      final results = await Future.wait<List<dynamic>>([
        _supabase
            .from('users')
            .select(
                'id, full_name, email, profile_photo, availability_status, specializations, avg_rating, total_resolved')
            .eq('role', 'engineer')
            .order('full_name'),
        _supabase.from('service_tickets').select('assigned_to').inFilter(
            'status', [
          'open',
          'assigned',
          'in_progress',
          'waiting_customer'
        ]).not('assigned_to', 'is', null).eq('is_deleted', false),
      ]);

      final engineers = List<Map<String, dynamic>>.from(results[0]);
      final tickets = List<Map<String, dynamic>>.from(results[1]);

      final counts = <String, int>{};
      for (final t in tickets) {
        final eid = t['assigned_to'] as String?;
        if (eid != null) counts[eid] = (counts[eid] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _engineers = engineers;
        _activeCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Failed to load engineers');
    }
  }

  Future<void> _assign(Map<String, dynamic> eng) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: dark ? Brand.darkCard : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Assign Engineer',
              style: TextStyle(
                  color: dark ? Brand.darkTextPrimary : Brand.royalBlue,
                  fontWeight: FontWeight.w700)),
          content: Text(
            'Assign "${eng['full_name']}" to this ticket?',
            style: TextStyle(
                color: dark ? Brand.darkTextSecondary : Colors.grey[700]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: dark ? Brand.darkTextSecondary : Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Brand.royalBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child:
                  const Text('Assign', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isAssigning = true);
    try {
      await _supabase.from('service_tickets').update({
        'assigned_to': eng['id'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.ticketId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAssigning = false);
      _snack('Assignment failed — $e');
    }
  }

  Future<void> _unassign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: dark ? Brand.darkCard : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Unassign Engineer',
              style: TextStyle(
                  color: Colors.orange[700], fontWeight: FontWeight.w700)),
          content: Text(
            'Remove the current engineer from this ticket? Status will revert to "open".',
            style: TextStyle(
                color: dark ? Brand.darkTextSecondary : Colors.grey[700]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: dark ? Brand.darkTextSecondary : Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child:
                  const Text('Unassign', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isAssigning = true);
    try {
      await _supabase.from('service_tickets').update({
        'assigned_to': null,
        'status': 'open',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.ticketId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAssigning = false);
      _snack('Failed to unassign — $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ── Helpers ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _engineers;
    final q = _search.toLowerCase();
    return _engineers.where((e) {
      final name = (e['full_name'] ?? '').toString().toLowerCase();
      final specs =
          (e['specializations'] as List?)?.join(' ').toLowerCase() ?? '';
      return name.contains(q) || specs.contains(q);
    }).toList();
  }

  Color _statusDot(String? status) {
    switch (status) {
      case 'available':
        return _availableColor;
      case 'busy':
        return _busyColor;
      default:
        return _offlineColor;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'available':
        return 'Available';
      case 'busy':
        return 'Busy';
      default:
        return 'Offline';
    }
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: dark ? Brand.darkBg : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: dark ? Brand.darkBorderLight : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                Icon(Icons.engineering_rounded,
                    color: dark ? Brand.darkTextPrimary : Brand.royalBlue,
                    size: 24),
                const SizedBox(width: 10),
                Text('Assign Engineer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: dark ? Brand.darkTextPrimary : Brand.royalBlue,
                    )),
                const Spacer(),
                if (widget.currentEngineerId != null)
                  TextButton.icon(
                    onPressed: _isAssigning ? null : _unassign,
                    icon: Icon(Icons.person_remove_rounded,
                        size: 18, color: Colors.orange[700]),
                    label: Text('Unassign',
                        style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(
                  color: dark ? Brand.darkTextPrimary : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search by name or specialization…',
                hintStyle: TextStyle(
                    color: dark ? Brand.darkTextSecondary : Colors.grey[500]),
                prefixIcon: Icon(Icons.search_rounded,
                    color: dark ? Brand.darkTextSecondary : Colors.grey),
                filled: true,
                fillColor: dark ? Brand.darkCard : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          // Loading overlay
          if (_isAssigning)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          // List
          Expanded(
            child: _isLoading ? _buildSkeleton(dark) : _buildList(dark),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool dark) {
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded,
                size: 48,
                color: dark ? Brand.darkTextSecondary : Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _search.isEmpty
                  ? 'No engineers found'
                  : 'No matches for "$_search"',
              style: TextStyle(
                  color: dark ? Brand.darkTextSecondary : Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildEngineerTile(list[i], dark),
    );
  }

  Widget _buildEngineerTile(Map<String, dynamic> eng, bool dark) {
    final id = eng['id'] as String;
    final name = eng['full_name'] ?? 'Unnamed';
    final status = eng['availability_status'] as String? ?? 'offline';
    final specs = List<String>.from(eng['specializations'] ?? []);
    final rating = (eng['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final resolved = eng['total_resolved'] as int? ?? 0;
    final active = _activeCounts[id] ?? 0;
    final isCurrent = id == widget.currentEngineerId;

    return Material(
      color: dark
          ? (isCurrent ? Brand.darkCardElevated : Brand.darkCard)
          : (isCurrent ? const Color(0xFFE8EEF9) : Colors.white),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: (_isAssigning || isCurrent) ? null : () => _assign(eng),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? Brand.lightGreen.withAlpha(153)
                  : (dark ? Brand.darkBorder : Colors.grey.withAlpha(38)),
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: dark
                        ? Brand.royalBlueLight.withAlpha(51)
                        : const Color(0xFFE8EEF9),
                    backgroundImage: eng['profile_photo'] != null
                        ? NetworkImage(eng['profile_photo'])
                        : null,
                    child: eng['profile_photo'] == null
                        ? Text(
                            name.toString().isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: dark
                                    ? Brand.royalBlueLight
                                    : Brand.royalBlue),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _statusDot(status),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: dark ? Brand.darkCard : Colors.white,
                            width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: dark
                                    ? Brand.darkTextPrimary
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Brand.lightGreen.withAlpha(38),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Current',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Brand.lightGreenDark)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Status label
                    Text(_statusLabel(status),
                        style: TextStyle(
                            fontSize: 12,
                            color: _statusDot(status),
                            fontWeight: FontWeight.w600)),
                    if (specs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: specs
                            .take(3)
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: dark
                                        ? Brand.royalBlueLight.withAlpha(31)
                                        : const Color(0xFFE8EEF9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(s,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: dark
                                              ? Brand.royalBlueLight
                                              : Brand.royalBlue,
                                          fontWeight: FontWeight.w500)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 14, color: Colors.amber[700]),
                        const SizedBox(width: 3),
                        Text(rating.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dark
                                    ? Brand.darkTextSecondary
                                    : Colors.grey[700])),
                        const SizedBox(width: 12),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 14,
                            color: dark
                                ? Brand.darkTextSecondary
                                : Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text('$resolved resolved',
                            style: TextStyle(
                                fontSize: 12,
                                color: dark
                                    ? Brand.darkTextSecondary
                                    : Colors.grey[600])),
                        const SizedBox(width: 12),
                        Icon(Icons.assignment_rounded,
                            size: 14,
                            color: active > 5
                                ? Colors.red[400]
                                : (dark
                                    ? Brand.darkTextSecondary
                                    : Colors.grey[500])),
                        const SizedBox(width: 3),
                        Text('$active active',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: active > 5
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active > 5
                                    ? Colors.red[400]
                                    : (dark
                                        ? Brand.darkTextSecondary
                                        : Colors.grey[600]))),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isCurrent)
                Icon(Icons.chevron_right_rounded,
                    color: dark ? Brand.darkTextSecondary : Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton(bool dark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: dark ? Brand.darkCard : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
