import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _eaAccent = Brand.lightGreenDark;

class EaPerformanceDashboard extends StatefulWidget {
  const EaPerformanceDashboard({super.key});

  @override
  State<EaPerformanceDashboard> createState() => _EaPerformanceDashboardState();
}

class _EaPerformanceDashboardState extends State<EaPerformanceDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Data
  List<Map<String, dynamic>> _engineers = [];
  List<Map<String, dynamic>> _kpiSnapshots = [];
  Map<String, dynamic> _teamSummary = {};
  bool _loading = true;
  String? _error;

  // Filters
  String? _selectedEngineerId;
  int _periodMonths = 3; // 1, 3, 6, 12

  static const _periodOptions = [
    (1, 'Last Month'),
    (3, 'Last 3 Months'),
    (6, 'Last 6 Months'),
    (12, 'Last Year'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final since = DateTime.now().subtract(Duration(days: _periodMonths * 30)).toIso8601String().substring(0, 10);

      final results = await Future.wait<dynamic>([
        // All active engineers
        SupabaseConfig.client
            .from('users')
            .select('id, full_name, profile_photo, employee_id, assigned_zone')
            .eq('role', 'engineer')
            .filter('date_terminated', 'is', null)
            .order('full_name'),

        // KPI snapshots in period
        _selectedEngineerId != null
            ? SupabaseConfig.client
                .from('engineer_kpi_snapshots')
                .select('*')
                .eq('engineer_id', _selectedEngineerId!)
                .gte('snapshot_month', since)
                .order('snapshot_month')
            : SupabaseConfig.client
                .from('engineer_kpi_snapshots')
                .select('*')
                .gte('snapshot_month', since)
                .order('snapshot_month'),
      ]);

      if (!mounted) return;

      final engineers = List<Map<String, dynamic>>.from(results[0]);
      final kpis = List<Map<String, dynamic>>.from(results[1]);

      // Build team summary from latest snapshot per engineer
      final latestByEngineer = <String, Map<String, dynamic>>{};
      for (final k in kpis) {
        final eid = k['engineer_id'] as String;
        final existing = latestByEngineer[eid];
        if (existing == null ||
            (k['snapshot_month'] as String).compareTo(existing['snapshot_month'] as String) > 0) {
          latestByEngineer[eid] = k;
        }
      }

      final summary = _computeTeamSummary(latestByEngineer.values.toList());

      setState(() {
        _engineers = engineers;
        _kpiSnapshots = kpis;
        _teamSummary = summary;
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

  Map<String, dynamic> _computeTeamSummary(List<Map<String, dynamic>> snapshots) {
    if (snapshots.isEmpty) return {};
    double totalAtt = 0, totalComp = 0, totalRating = 0;
    int ratingCount = 0;
    int totalJobs = 0, totalCompletedJobs = 0;

    for (final s in snapshots) {
      totalAtt += (s['on_time_rate'] as num?)?.toDouble() ?? 0;
      final sTotal = (s['total_jobs'] as num?)?.toInt() ?? 0;
      totalComp += sTotal > 0 ? ((s['completed_jobs'] as num?)?.toDouble() ?? 0) / sTotal * 100.0 : 0.0;
      final r = (s['avg_rating'] as num?)?.toDouble();
      if (r != null && r > 0) {
        totalRating += r;
        ratingCount++;
      }
      totalJobs += (s['total_jobs'] as int?) ?? 0;
      totalCompletedJobs += (s['completed_jobs'] as int?) ?? 0;
    }
    final n = snapshots.length;
    return {
      'avg_attendance': totalAtt / n,
      'avg_completion': totalComp / n,
      'avg_rating': ratingCount > 0 ? totalRating / ratingCount : 0.0,
      'total_jobs': totalJobs,
      'completed_jobs': totalCompletedJobs,
      'engineer_count': n,
    };
  }

  // Latest KPI for a given engineer
  Map<String, dynamic>? _latestKpi(String engineerId) {
    final snapshots = _kpiSnapshots.where((k) => k['engineer_id'] == engineerId).toList();
    if (snapshots.isEmpty) return null;
    snapshots.sort((a, b) =>
        (b['snapshot_month'] as String).compareTo(a['snapshot_month'] as String));
    return snapshots.first;
  }

  // KPI history for selected engineer (time series)
  List<Map<String, dynamic>> _engineerHistory(String engineerId) {
    final snapshots = _kpiSnapshots.where((k) => k['engineer_id'] == engineerId).toList();
    snapshots.sort((a, b) =>
        (a['snapshot_month'] as String).compareTo(b['snapshot_month'] as String));
    return snapshots;
  }

  List<Map<String, dynamic>> get _filteredEngineers {
    if (_selectedEngineerId != null) {
      return _engineers.where((e) => e['id'] == _selectedEngineerId).toList();
    }
    return _engineers;
  }

  void _showPeriodSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time Period',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.text(context),
                )),
            const SizedBox(height: 16),
            RadioGroup<int>(
              groupValue: _periodMonths,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _periodMonths = v);
                Navigator.pop(context);
                _load();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _periodOptions
                    .map((opt) => RadioListTile<int>(
                          value: opt.$1,
                          title: Text(opt.$2),
                          activeColor: _eaAccent,
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEngineerPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
      ),
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          builder: (_, ctrl) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter by Engineer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.text(context),
                    )),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('All Engineers'),
                  leading: const Icon(Icons.groups_rounded),
                  selected: _selectedEngineerId == null,
                  selectedColor: _eaAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
                  onTap: () {
                    setState(() => _selectedEngineerId = null);
                    Navigator.pop(context);
                    _load();
                  },
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    itemCount: _engineers.length,
                    itemBuilder: (_, i) {
                      final eng = _engineers[i];
                      final selected = _selectedEngineerId == eng['id'];
                      return ListTile(
                        leading: _miniAvatar(eng['profile_photo'] as String?, eng['full_name'] as String? ?? ''),
                        title: Text(eng['full_name'] as String? ?? 'Engineer'),
                        subtitle: Text(eng['assigned_zone'] as String? ?? ''),
                        selected: selected,
                        selectedColor: _eaAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
                        onTap: () {
                          setState(() => _selectedEngineerId = eng['id'] as String);
                          Navigator.pop(context);
                          _load();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel = _periodOptions.firstWhere((p) => p.$1 == _periodMonths).$2;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: 'Performance',
        accent: HeroAccent.emerald,
        actions: [
          TextButton.icon(
            onPressed: _showEngineerPicker,
            icon: const Icon(Icons.person_search_rounded, size: 18, color: Colors.white),
            label: Text(
              _selectedEngineerId != null
                  ? (_engineers.firstWhere((e) => e['id'] == _selectedEngineerId,
                      orElse: () => {})['full_name'] as String? ?? 'Engineer')
                  : 'All',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, size: 20, color: Colors.white),
            tooltip: periodLabel,
            onPressed: _showPeriodSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Engineers'),
            Tab(text: 'Trends'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _eaAccent,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _OverviewTab(
                        summary: _teamSummary,
                        engineers: _filteredEngineers,
                        getLatestKpi: _latestKpi,
                      ),
                      _EngineersTab(
                        engineers: _filteredEngineers,
                        getLatestKpi: _latestKpi,
                      ),
                      _TrendsTab(
                        engineers: _filteredEngineers,
                        kpiSnapshots: _kpiSnapshots,
                        selectedEngineerId: _selectedEngineerId,
                        getHistory: _engineerHistory,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _miniAvatar(String? url, String name) {
    const size = 36.0;
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
      decoration: BoxDecoration(color: _eaAccent.withAlpha(40), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: _eaAccent)),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> engineers;
  final Map<String, dynamic>? Function(String) getLatestKpi;

  const _OverviewTab({
    required this.summary,
    required this.engineers,
    required this.getLatestKpi,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 56, color: AdminColors.textHint(context)),
            const SizedBox(height: 12),
            Text('No KPI data for this period',
                style: TextStyle(color: AdminColors.textSub(context))),
          ],
        ),
      );
    }

    final avgAtt = (summary['avg_attendance'] as double? ?? 0);
    final avgComp = (summary['avg_completion'] as double? ?? 0);
    final avgRating = (summary['avg_rating'] as double? ?? 0);
    final totalJobs = summary['total_jobs'] as int? ?? 0;
    final completedJobs = summary['completed_jobs'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // KPI cards row
        Row(
          children: [
            Expanded(child: _KpiCard(label: 'Avg Attendance', value: '${avgAtt.toStringAsFixed(1)}%', icon: Icons.event_available_rounded, color: StatusColors.resolved)),
            const SizedBox(width: 10),
            Expanded(child: _KpiCard(label: 'Avg Completion', value: '${avgComp.toStringAsFixed(1)}%', icon: Icons.task_alt_rounded, color: _eaAccent)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _KpiCard(label: 'Avg Rating', value: avgRating > 0 ? '${avgRating.toStringAsFixed(1)} ★' : '—', icon: Icons.star_rounded, color: AdminColors.warning)),
            const SizedBox(width: 10),
            Expanded(child: _KpiCard(label: 'Total Jobs', value: '$completedJobs / $totalJobs', icon: Icons.work_outline_rounded, color: StatusColors.assigned)),
          ],
        ),

        const SizedBox(height: 20),

        // Team coverage
        _sectionHeader(context, 'Team Coverage', '${engineers.length} engineers tracked'),

        const SizedBox(height: 10),

        // Top performers
        if (engineers.isNotEmpty) ...[
          _TopPerformers(engineers: engineers, getLatestKpi: getLatestKpi),
          const SizedBox(height: 20),

          // Attendance distribution pie
          _sectionHeader(context, 'KPI Distribution', ''),
          const SizedBox(height: 10),
          _AttendancePieCard(engineers: engineers, getLatestKpi: getLatestKpi),
        ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String sub) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AdminColors.text(context),
            )),
        if (sub.isNotEmpty) ...[
          const Spacer(),
          Text(sub, style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
        boxShadow: isDark
            ? []
            : [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AdminColors.text(context),
              )),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
        ],
      ),
    );
  }
}

class _TopPerformers extends StatelessWidget {
  final List<Map<String, dynamic>> engineers;
  final Map<String, dynamic>? Function(String) getLatestKpi;

  const _TopPerformers({required this.engineers, required this.getLatestKpi});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final ranked = engineers
        .map((e) => (e, getLatestKpi(e['id'] as String)))
        .where((pair) => pair.$2 != null)
        .toList()
      ..sort((a, b) {
        final aScore = _score(a.$2!);
        final bScore = _score(b.$2!);
        return bScore.compareTo(aScore);
      });

    if (ranked.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 18, color: AdminColors.warning),
                const SizedBox(width: 6),
                Text('Top Performers',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.text(context),
                    )),
              ],
            ),
          ),
          const Divider(height: 1),
          ...ranked.take(5).toList().asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final eng = entry.value.$1;
            final kpi = entry.value.$2!;
            return _PerformerRow(rank: rank, engineer: eng, kpi: kpi);
          }),
        ],
      ),
    );
  }

  double _score(Map<String, dynamic> kpi) {
    final att = (kpi['on_time_rate'] as num?)?.toDouble() ?? 0;
    final compTotal = (kpi['total_jobs'] as num?)?.toInt() ?? 0;
    final comp = compTotal > 0 ? ((kpi['completed_jobs'] as num?)?.toDouble() ?? 0) / compTotal * 100.0 : 0.0;
    final rating = (kpi['avg_rating'] as num?)?.toDouble() ?? 0;
    return att * 0.4 + comp * 0.4 + (rating / 5 * 100) * 0.2;
  }
}

class _PerformerRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> engineer;
  final Map<String, dynamic> kpi;

  const _PerformerRow({required this.rank, required this.engineer, required this.kpi});

  @override
  Widget build(BuildContext context) {
    final url = engineer['profile_photo'] as String?;
    final name = engineer['full_name'] as String? ?? 'Engineer';
    final att = (kpi['on_time_rate'] as num?)?.toDouble() ?? 0;
    final compTotal = (kpi['total_jobs'] as num?)?.toInt() ?? 0;
    final comp = compTotal > 0 ? ((kpi['completed_jobs'] as num?)?.toDouble() ?? 0) / compTotal * 100.0 : 0.0;
    final rating = (kpi['avg_rating'] as num?)?.toDouble();

    Color rankColor = AdminColors.textHint(context);
    if (rank == 1) rankColor = TierColors.gold;
    if (rank == 2) rankColor = TierColors.silver;
    if (rank == 3) rankColor = TierColors.bronze;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: rankColor,
                )),
          ),
          const SizedBox(width: 8),
          _avatar(url, name, 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AdminColors.text(context),
                    )),
                Row(
                  children: [
                    _miniStat('Att ${att.toStringAsFixed(0)}%', StatusColors.resolved),
                    const SizedBox(width: 8),
                    _miniStat('Comp ${comp.toStringAsFixed(0)}%', _eaAccent),
                    if (rating != null && rating > 0) ...[
                      const SizedBox(width: 8),
                      _miniStat('${rating.toStringAsFixed(1)}★', AdminColors.warning),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String text, Color color) {
    return Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500));
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
      decoration: BoxDecoration(color: _eaAccent.withAlpha(40), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: _eaAccent)),
    );
  }
}

class _AttendancePieCard extends StatelessWidget {
  final List<Map<String, dynamic>> engineers;
  final Map<String, dynamic>? Function(String) getLatestKpi;

  const _AttendancePieCard({required this.engineers, required this.getLatestKpi});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Bucket engineers by attendance rate
    int high = 0, medium = 0, low = 0, noData = 0;
    for (final eng in engineers) {
      final kpi = getLatestKpi(eng['id'] as String);
      if (kpi == null) {
        noData++;
        continue;
      }
      final att = (kpi['on_time_rate'] as num?)?.toDouble() ?? 0;
      if (att >= 80) {
        high++;
      } else if (att >= 60) {
        medium++;
      } else {
        low++;
      }
    }

    final total = engineers.length;
    if (total == 0) return const SizedBox.shrink();

    final sections = <PieChartSectionData>[
      if (high > 0)
        PieChartSectionData(
          value: high.toDouble(),
          color: StatusColors.resolved,
          title: '$high',
          radius: 55,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      if (medium > 0)
        PieChartSectionData(
          value: medium.toDouble(),
          color: AdminColors.warning,
          title: '$medium',
          radius: 55,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      if (low > 0)
        PieChartSectionData(
          value: low.toDouble(),
          color: AdminColors.error,
          title: '$low',
          radius: 55,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      if (noData > 0)
        PieChartSectionData(
          value: noData.toDouble(),
          color: Brand.subtleLight,
          title: '$noData',
          radius: 55,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Column(
        children: [
          Text('Attendance Distribution',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AdminColors.text(context),
              )),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 40)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (high > 0) _legend('≥80% (Good)', StatusColors.resolved),
              if (medium > 0) _legend('60–79% (Fair)', AdminColors.warning),
              if (low > 0) _legend('<60% (Poor)', AdminColors.error),
              if (noData > 0) _legend('No Data', Brand.subtleLight),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ── Engineers Tab ─────────────────────────────────────────────────────────────

class _EngineersTab extends StatelessWidget {
  final List<Map<String, dynamic>> engineers;
  final Map<String, dynamic>? Function(String) getLatestKpi;

  const _EngineersTab({required this.engineers, required this.getLatestKpi});

  @override
  Widget build(BuildContext context) {
    if (engineers.isEmpty) {
      return Center(
        child: Text('No engineers found', style: TextStyle(color: AdminColors.textSub(context))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: engineers.length,
      itemBuilder: (_, i) {
        final eng = engineers[i];
        final kpi = getLatestKpi(eng['id'] as String);
        return _EngineerKpiCard(engineer: eng, kpi: kpi);
      },
    );
  }
}

class _EngineerKpiCard extends StatelessWidget {
  final Map<String, dynamic> engineer;
  final Map<String, dynamic>? kpi;

  const _EngineerKpiCard({required this.engineer, this.kpi});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = engineer['profile_photo'] as String?;
    final name = engineer['full_name'] as String? ?? 'Engineer';
    final zone = engineer['assigned_zone'] as String?;
    final empId = engineer['employee_id'] as String?;

    final att = (kpi?['on_time_rate'] as num?)?.toDouble();
    final rating = (kpi?['avg_rating'] as num?)?.toDouble();
    final totalJobs = (kpi?['total_jobs'] as num?)?.toInt();
    final completedJobs = (kpi?['completed_jobs'] as num?)?.toInt();
    final comp = (totalJobs != null && totalJobs > 0)
        ? (completedJobs ?? 0) / totalJobs * 100.0
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
        boxShadow: isDark
            ? []
            : [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Engineer header
          Row(
            children: [
              _avatar(url, name, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AdminColors.text(context),
                        )),
                    if (empId != null || zone != null)
                      Text(
                        [if (empId != null) '#$empId', if (zone != null) zone].join(' · '),
                        style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                      ),
                  ],
                ),
              ),
              if (rating != null && rating > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Brand.slateLight,
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: AdminColors.warning),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: StatusColors.warningDark,
                          )),
                    ],
                  ),
                ),
            ],
          ),

          if (kpi == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('No KPI data for this period',
                  style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
            )
          else ...[
            const SizedBox(height: 14),

            // Attendance bar
            _ProgressBar(
              label: 'Attendance',
              value: (att ?? 0) / 100,
              displayValue: att != null ? '${att.toStringAsFixed(1)}%' : '—',
              color: StatusColors.resolved,
            ),
            const SizedBox(height: 8),

            // Completion bar
            _ProgressBar(
              label: 'Job Completion',
              value: (comp ?? 0) / 100,
              displayValue: comp != null ? '${comp.toStringAsFixed(1)}%' : '—',
              color: _eaAccent,
            ),

            if (totalJobs != null) ...[
              const SizedBox(height: 10),
              Text(
                'Jobs: $completedJobs completed of $totalJobs total',
                style: TextStyle(fontSize: 12, color: AdminColors.textHint(context)),
              ),
            ],
          ],
        ],
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
          placeholder: (_, __) => _fallback(name, size),
          errorWidget: (_, __, ___) => _fallback(name, size),
        ),
      );
    }
    return _fallback(name, size);
  }

  Widget _fallback(String name, double size) {
    final initials = name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _eaAccent.withAlpha(40), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: _eaAccent)),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label;
  final double value; // 0.0 – 1.0
  final String displayValue;
  final Color color;

  const _ProgressBar({
    required this.label,
    required this.value,
    required this.displayValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: AdminColors.textSub(context))),
            Text(displayValue,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(Brand.r(4)),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            backgroundColor: AdminColors.border(context),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ── Trends Tab ────────────────────────────────────────────────────────────────

class _TrendsTab extends StatelessWidget {
  final List<Map<String, dynamic>> engineers;
  final List<Map<String, dynamic>> kpiSnapshots;
  final String? selectedEngineerId;
  final List<Map<String, dynamic>> Function(String) getHistory;

  const _TrendsTab({
    required this.engineers,
    required this.kpiSnapshots,
    required this.selectedEngineerId,
    required this.getHistory,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (selectedEngineerId != null) {
      return _SingleEngineerTrends(
        engineerId: selectedEngineerId!,
        history: getHistory(selectedEngineerId!),
        isDark: isDark,
      );
    }

    // Team aggregate trend — group snapshots by month
    return _TeamTrends(kpiSnapshots: kpiSnapshots, isDark: isDark);
  }
}

class _SingleEngineerTrends extends StatelessWidget {
  final String engineerId;
  final List<Map<String, dynamic>> history;
  final bool isDark;

  const _SingleEngineerTrends({
    required this.engineerId,
    required this.history,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Text('No trend data available',
            style: TextStyle(color: AdminColors.textSub(context))),
      );
    }

    // Build line chart data
    final attSpots = <FlSpot>[];
    final compSpots = <FlSpot>[];

    for (var i = 0; i < history.length; i++) {
      final k = history[i];
      final att = (k['on_time_rate'] as num?)?.toDouble() ?? 0;
      final kTotal = (k['total_jobs'] as num?)?.toInt() ?? 0;
      final comp = kTotal > 0 ? ((k['completed_jobs'] as num?)?.toDouble() ?? 0) / kTotal * 100.0 : 0.0;
      attSpots.add(FlSpot(i.toDouble(), att));
      compSpots.add(FlSpot(i.toDouble(), comp));
    }

    final labels = history
        .map((k) {
          try {
            return DateFormat('MMM').format(DateTime.parse(k['snapshot_month'] as String));
          } catch (_) {
            return '';
          }
        })
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _TrendCard(
          title: 'Attendance & Completion Trend',
          isDark: isDark,
          chart: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AdminColors.border(context).withAlpha(100),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 20,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                      return Text(
                        labels[idx],
                        style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: attSpots,
                  isCurved: true,
                  color: StatusColors.resolved,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: StatusColors.resolved.withAlpha(25),
                  ),
                ),
                LineChartBarData(
                  spots: compSpots,
                  isCurved: true,
                  color: _eaAccent,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _eaAccent.withAlpha(25),
                  ),
                ),
              ],
            ),
          ),
          legend: [
            _TrendLegendItem(label: 'Attendance', color: StatusColors.resolved),
            _TrendLegendItem(label: 'Completion', color: _eaAccent),
          ],
        ),
      ],
    );
  }
}

class _TeamTrends extends StatelessWidget {
  final List<Map<String, dynamic>> kpiSnapshots;
  final bool isDark;

  const _TeamTrends({required this.kpiSnapshots, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (kpiSnapshots.isEmpty) {
      return Center(
        child: Text('No trend data available',
            style: TextStyle(color: AdminColors.textSub(context))),
      );
    }

    // Group by month, compute average attendance and completion
    final byMonth = <String, List<Map<String, dynamic>>>{};
    for (final k in kpiSnapshots) {
      final date = k['snapshot_month'] as String? ?? '';
      if (date.length < 7) continue;
      final month = date.substring(0, 7);
      byMonth.putIfAbsent(month, () => []).add(k);
    }

    final months = byMonth.keys.toList()..sort();
    final attSpots = <FlSpot>[];
    final compSpots = <FlSpot>[];
    final labels = <String>[];

    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      final snapshots = byMonth[m]!;
      double totalAtt = 0, totalComp = 0;
      for (final s in snapshots) {
        totalAtt += (s['on_time_rate'] as num?)?.toDouble() ?? 0;
        final sTotal = (s['total_jobs'] as num?)?.toInt() ?? 0;
      totalComp += sTotal > 0 ? ((s['completed_jobs'] as num?)?.toDouble() ?? 0) / sTotal * 100.0 : 0.0;
      }
      final n = snapshots.length;
      attSpots.add(FlSpot(i.toDouble(), totalAtt / n));
      compSpots.add(FlSpot(i.toDouble(), totalComp / n));
      try {
        labels.add(DateFormat('MMM yy').format(DateTime.parse('$m-01')));
      } catch (_) {
        labels.add(m);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _TrendCard(
          title: 'Team Average Trend',
          isDark: isDark,
          chart: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AdminColors.border(context).withAlpha(100),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 20,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                      return Text(
                        labels[idx],
                        style: TextStyle(fontSize: 11, color: AdminColors.textHint(context)),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: attSpots,
                  isCurved: true,
                  color: StatusColors.resolved,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: StatusColors.resolved.withAlpha(25),
                  ),
                ),
                LineChartBarData(
                  spots: compSpots,
                  isCurved: true,
                  color: _eaAccent,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _eaAccent.withAlpha(25),
                  ),
                ),
              ],
            ),
          ),
          legend: [
            _TrendLegendItem(label: 'Avg Attendance', color: StatusColors.resolved),
            _TrendLegendItem(label: 'Avg Completion', color: _eaAccent),
          ],
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;
  final bool isDark;
  final Widget chart;
  final List<Widget> legend;

  const _TrendCard({
    required this.title,
    required this.isDark,
    required this.chart,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AdminColors.text(context),
              )),
          const SizedBox(height: 16),
          SizedBox(height: 200, child: chart),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            children: legend,
          ),
        ],
      ),
    );
  }
}

class _TrendLegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _TrendLegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 3,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Brand.r(2))),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: AdminColors.textSub(context))),
      ],
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────

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
            Text('Failed to load performance data',
                style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.text(context))),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AdminColors.textSub(context))),
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
