// lib/screens/admin/admin_hot_leads_page.dart
//
// Hot Leads dashboard (v22 enhancement on top of the Journey Progress system).
// Lists every active suggestion at 75%+ across all customers, sorted by how
// long it has sat at the same score — so the marketer can prioritise the
// customers who are closest to "Ready" but haven't been moved recently.
//
// Tap a card → opens the customer detail page so the marketer can move the
// slider, send a nudge, or mark the outcome.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'customer_detail_page.dart';

class AdminHotLeadsPage extends StatefulWidget {
  const AdminHotLeadsPage({super.key});

  @override
  State<AdminHotLeadsPage> createState() => _AdminHotLeadsPageState();
}

class _AdminHotLeadsPageState extends State<AdminHotLeadsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;
  int _minScore = 75; // chip filter: 50 / 75 / 100

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await SupabaseConfig.client
          .from('machine_suggestions')
          .select(
            'id, journey_score, stage_note, '
            'score_updated_at, created_at, next_followup_at, '
            'outcome, milestone_100_sent, '
            'customer:users!customer_id(id, full_name, company_name, profile_photo, email), '
            'batch:suggestion_batches!batch_id('
            'note, machine:machine_catalog!machine_id(id, machine_name, image_url)'
            ')',
          )
          .eq('is_active', true)
          .filter('outcome', 'is', null)
          .gte('journey_score', _minScore)
          .order('journey_score', ascending: false)
          .order('score_updated_at', ascending: true, nullsFirst: true)
          .limit(200);

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load: $e';
        _isLoading = false;
      });
    }
  }

  // ─── Helpers ──────────────────────────────────────────────
  String _staleSince(DateTime? when) {
    if (when == null) return 'Never moved';
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 1) return '${diff.inDays}d at this score';
    if (diff.inHours >= 1) return '${diff.inHours}h at this score';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m at this score';
    return 'Just now';
  }

  Color _staleColor(DateTime? when) {
    if (when == null) return AdminColors.error;
    final days = DateTime.now().difference(when).inDays;
    if (days >= 7) return AdminColors.error;
    if (days >= 3) return AdminColors.warning;
    return AdminColors.success;
  }

  Color _scoreColor(int s) {
    if (s >= 100) return AdminColors.success;
    if (s >= 75) return StatusColors.materialGreen;
    if (s >= 50) return AdminColors.warning;
    return AdminColors.info;
  }

  // ─── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Hot Leads',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(isDark),
          _buildChips(isDark),
          Expanded(child: _buildList(isDark)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final readyCount = _items.where((m) => (m['journey_score'] as num? ?? 0) >= 100).length;
    final almostCount = _items.where((m) {
      final s = (m['journey_score'] as num? ?? 0).toInt();
      return s >= 75 && s < 100;
    }).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _kpi(
              isDark,
              icon: Icons.local_fire_department_rounded,
              color: AdminColors.error,
              label: 'Ready',
              value: '$readyCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpi(
              isDark,
              icon: Icons.bolt_rounded,
              color: AdminColors.warning,
              label: 'Almost ready',
              value: '$almostCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpi(
              isDark,
              icon: Icons.people_alt_rounded,
              color: AdminColors.info,
              label: 'In list',
              value: '${_items.length}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(bool isDark, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 50 : 30),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: AdminColors.textSub(context))),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.text(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(bool isDark) {
    final options = const [50, 75, 100];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = options[i];
          final sel = _minScore == v;
          final c = _scoreColor(v);
          return GestureDetector(
            onTap: () {
              setState(() => _minScore = v);
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? c.withAlpha(isDark ? 50 : 30) : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: Border.all(
                  color: sel ? c : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: sel ? 1.4 : 1,
                ),
              ),
              child: Text(
                v == 100 ? 'Ready (100%)' : '≥ $v%',
                style: TextStyle(
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? c : AdminColors.text(context),
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: AdminColors.error)),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_outlined,
                  size: 56, color: AdminColors.textHint(context)),
              const SizedBox(height: 12),
              Text(
                'No active leads ≥ $_minScore%',
                style: TextStyle(color: AdminColors.textSub(context)),
              ),
              const SizedBox(height: 4),
              Text(
                'When you move a customer\'s journey to this threshold,\nthey\'ll appear here so you can prioritise the follow-up.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AdminColors.textHint(context)),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_items[i], isDark),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> m, bool isDark) {
    final customer = m['customer'] as Map<String, dynamic>?;
    final batch = m['batch'] as Map<String, dynamic>?;
    final machine = batch?['machine'] as Map<String, dynamic>?;
    final score = (m['journey_score'] as num? ?? 0).toInt();
    final updatedAt = m['score_updated_at'] != null
        ? DateTime.tryParse(m['score_updated_at'] as String)
        : null;
    final stage = m['stage_note'] as String?;
    final scoreColor = _scoreColor(score);
    final staleColor = _staleColor(updatedAt);
    final customerId = customer?['id']?.toString();
    final fullName = customer?['full_name']?.toString() ?? 'Customer';
    final companyName = customer?['company_name']?.toString();
    final photo = customer?['profile_photo']?.toString();
    final machineName = machine?['machine_name']?.toString();
    final next = m['next_followup_at'] != null
        ? DateTime.tryParse(m['next_followup_at'] as String)
        : null;

    return InkWell(
      onTap: customerId == null
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomerDetailPage(customerId: customerId),
                ),
              );
              if (mounted) _load(); // refresh after returning
            },
      borderRadius: BorderRadius.circular(Brand.r(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + name + score chip
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scoreColor.withAlpha(40),
                backgroundImage: (photo != null && photo.isNotEmpty)
                    ? CachedNetworkImageProvider(photo)
                    : null,
                child: (photo == null || photo.isEmpty)
                    ? Text(
                        fullName.isNotEmpty
                            ? fullName.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (companyName != null && companyName.isNotEmpty)
                      Text(
                        companyName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scoreColor.withAlpha(35),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                child: Text(
                  '$score%',
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 10),

            // Machine row
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Brand.r(8)),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: (machine?['image_url'] != null &&
                          (machine!['image_url'] as String).isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: machine['image_url'] as String,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.precision_manufacturing_rounded,
                            size: 18,
                            color: AdminColors.textHint(context),
                          ),
                        )
                      : Container(
                          color: AdminColors.textHint(context).withAlpha(30),
                          child: Icon(
                            Icons.precision_manufacturing_rounded,
                            size: 18,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  machineName ?? 'Machine removed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.text(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),

            if (stage != null && stage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"$stage"',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AdminColors.textSub(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),

            // Bottom row: stale-since + next follow-up
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(
                  icon: Icons.access_time_rounded,
                  label: _staleSince(updatedAt),
                  color: staleColor,
                ),
                if (next != null)
                  _pill(
                    icon: Icons.alarm_rounded,
                    label: 'Follow-up ${_relativeDate(next)}',
                    color: AdminColors.info,
                  ),
                if (score >= 100)
                  _pill(
                    icon: Icons.flag_circle_rounded,
                    label: 'Ready to close',
                    color: AdminColors.error,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(Brand.r(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _relativeDate(DateTime when) {
    final now = DateTime.now().toUtc();
    final diff = when.toUtc().difference(now);
    if (diff.inDays > 1) return 'in ${diff.inDays}d';
    if (diff.inHours > 1) return 'in ${diff.inHours}h';
    if (diff.inMinutes > 1) return 'in ${diff.inMinutes}m';
    if (diff.inMinutes < -60 * 24) return '${-diff.inDays}d ago';
    if (diff.inMinutes < -60) return '${-diff.inHours}h ago';
    if (diff.inMinutes < 0) return 'overdue';
    return 'today';
  }
}
