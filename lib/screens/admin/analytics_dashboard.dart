import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../widgets/common/ic_icons.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  // ─── Constants ─────────────────────────────────────────────
  static const _primaryColor = Brand.royalBlue;
  static const _accentColor = Brand.lightGreen;

  static const _statusColors = {
    'open': Color(0xFFF59E0B),
    'assigned': Color(0xFF3B82F6),
    'in_progress': Brand.royalBlue,
    'waiting_customer': Color(0xFFEF8C22),
    'resolved': Brand.lightGreen,
    'closed': Color(0xFF6B7280),
  };

  static const _priorityColors = {
    'urgent': Color(0xFFEF4444),
    'high': Color(0xFFF97316),
    'medium': Color(0xFF3B82F6),
    'low': Color(0xFF22C55E),
  };

  static const _categoryPalette = [
    Brand.royalBlue,
    Brand.lightGreen,
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  // ─── State ─────────────────────────────────────────────────
  bool _isLoading = true;
  String _period = '30d';

  // Raw data
  List<Map<String, dynamic>> _allTickets = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _engineers = [];
  Map<String, String> _categoryMap = {};

  // Computed (filtered by period)
  List<Map<String, dynamic>> _filteredTickets = [];
  int _totalCount = 0;
  Map<String, int> _statusCounts = {};
  Map<String, int> _priorityCounts = {};
  Map<String, int> _typeCounts = {};
  Map<String, int> _categoryCounts = {};
  double _avgResolutionHours = 0;
  double _avgResponseMinutes = 0;
  double _avgRating = 0;
  int _ratingCount = 0;
  double _resolutionRate = 0;
  double _escalationRate = 0;

  // Chart data
  List<String> _volumeLabels = [];
  List<double> _volumeValues = [];
  List<String> _growthLabels = [];
  List<double> _growthValues = [];
  List<Map<String, dynamic>> _engineerStats = [];

  // Touch indices
  int _touchedStatusIndex = -1;
  int _touchedCategoryIndex = -1;

  // ─── Dark Mode ─────────────────────────────────────────────
  bool _isDark = false;

  Color get _scaffoldBg => _Brand.canvas(isDark);
  Color get _cardBg => _Brand.surface(isDark);
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : const Color(0xFF1A1A2E);
  Color get _textSecondary =>
      _isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8);
  Color get _borderColor => _isDark ? Brand.darkBorder : Brand.borderLight;
  Color get _dividerColor =>
      _isDark ? Brand.darkBorderLight : const Color(0xFFE2E8F0);
  Color get _gridColor => _isDark ? Brand.darkBorder : const Color(0xFFF1F5F9);
  Color get _barBg =>
      _isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9);
  Color get _tooltipBg => _isDark ? Brand.darkCardElevated : Colors.white;

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

  // ─── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('service_tickets')
            .select(
              'id, created_at, status, priority, ticket_type, assigned_to, '
              'first_response_at, closed_at, customer_rating, escalated, '
              'catalog_machine_id, customer_machine_id',
            )
            .eq('is_deleted', false)
            .order('created_at'),
        SupabaseConfig.client
            .from('users')
            .select('id, created_at')
            .eq('role', 'customer')
            .order('created_at'),
        SupabaseConfig.client
            .from('users')
            .select('id, full_name, avg_rating, total_resolved')
            .eq('role', 'engineer')
            .order('full_name'),
        SupabaseConfig.client
            .from('machine_catalog')
            .select('id, category')
            .eq('is_active', true),
      ]);

      if (!mounted) return;

      _allTickets = List<Map<String, dynamic>>.from(results[0] as List);
      _customers = List<Map<String, dynamic>>.from(results[1] as List);
      _engineers = List<Map<String, dynamic>>.from(results[2] as List);

      final catalogs = List<Map<String, dynamic>>.from(results[3] as List);
      final newCategoryMap = <String, String>{};
      for (final c in catalogs) {
        if (c['id'] != null) {
          newCategoryMap[c['id'].toString()] =
              (c['category'] ?? 'Other').toString();
        }
      }
      _categoryMap = newCategoryMap;

      _computeAnalytics();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Error loading analytics: $e', isError: true);
    }
  }

  // ─── COMPUTE ANALYTICS ────────────────────────────────────
  void _computeAnalytics() {
    // Filter by period
    final now = DateTime.now();
    DateTime? cutoff;
    switch (_period) {
      case '7d':
        cutoff = now.subtract(const Duration(days: 7));
        break;
      case '30d':
        cutoff = now.subtract(const Duration(days: 30));
        break;
      case '90d':
        cutoff = now.subtract(const Duration(days: 90));
        break;
      default:
        cutoff = null;
    }

    _filteredTickets = cutoff == null
        ? List<Map<String, dynamic>>.from(_allTickets)
        : _allTickets.where((t) {
            final d = DateTime.tryParse(t['created_at'] ?? '');
            return d != null && d.isAfter(cutoff!);
          }).toList();

    _totalCount = _filteredTickets.length;

    // Reset counts
    _statusCounts = {
      'open': 0,
      'assigned': 0,
      'in_progress': 0,
      'waiting_customer': 0,
      'resolved': 0,
      'closed': 0,
    };
    _priorityCounts = {
      'urgent': 0,
      'high': 0,
      'medium': 0,
      'low': 0,
    };
    _typeCounts = {
      'support': 0,
      'order': 0,
      'inquiry': 0,
    };
    _categoryCounts = {};

    int resolutionTimeSum = 0;
    int resolutionCount = 0;
    int responseTimeSum = 0;
    int responseCount = 0;
    int ratingSum = 0;
    _ratingCount = 0;
    int escalatedCount = 0;

    final engineerResolved = <String, int>{};

    for (final t in _filteredTickets) {
      final status = (t['status'] ?? 'open').toString();
      final priority = (t['priority'] ?? 'medium').toString();
      final type = (t['ticket_type'] ?? 'support').toString();

      _statusCounts[status] = (_statusCounts[status] ?? 0) + 1;
      _priorityCounts[priority] = (_priorityCounts[priority] ?? 0) + 1;
      _typeCounts[type] = (_typeCounts[type] ?? 0) + 1;

      // Resolution time
      if (t['closed_at'] != null &&
          (status == 'resolved' || status == 'closed')) {
        final created = DateTime.tryParse(t['created_at'] ?? '');
        final closed = DateTime.tryParse(t['closed_at'].toString());
        if (created != null && closed != null) {
          resolutionTimeSum += closed.difference(created).inHours;
          resolutionCount++;
        }
      }

      // Response time
      if (t['first_response_at'] != null) {
        final created = DateTime.tryParse(t['created_at'] ?? '');
        final responded = DateTime.tryParse(t['first_response_at'].toString());
        if (created != null && responded != null) {
          responseTimeSum += responded.difference(created).inMinutes;
          responseCount++;
        }
      }

      // Rating
      if (t['customer_rating'] != null) {
        ratingSum += (t['customer_rating'] as num).toInt();
        _ratingCount++;
      }

      // Escalated
      if (t['escalated'] == true) escalatedCount++;

      // Category
      final catalogId = t['catalog_machine_id']?.toString();
      if (catalogId != null && _categoryMap.containsKey(catalogId)) {
        final cat = _categoryMap[catalogId]!;
        _categoryCounts[cat] = (_categoryCounts[cat] ?? 0) + 1;
      }

      // Engineer resolved
      if (t['assigned_to'] != null &&
          (status == 'resolved' || status == 'closed')) {
        final eid = t['assigned_to'].toString();
        engineerResolved[eid] = (engineerResolved[eid] ?? 0) + 1;
      }
    }

    _avgResolutionHours =
        resolutionCount > 0 ? resolutionTimeSum / resolutionCount : 0;
    _avgResponseMinutes =
        responseCount > 0 ? responseTimeSum / responseCount : 0;
    _avgRating = _ratingCount > 0 ? ratingSum / _ratingCount : 0;

    final resolvedClosed =
        (_statusCounts['resolved'] ?? 0) + (_statusCounts['closed'] ?? 0);
    _resolutionRate =
        _totalCount > 0 ? (resolvedClosed / _totalCount * 100) : 0;
    _escalationRate =
        _totalCount > 0 ? (escalatedCount / _totalCount * 100) : 0;

    // Engineer stats
    _engineerStats = _engineers.map((eng) {
      final eid = eng['id'].toString();
      return {
        'name': eng['full_name'] ?? 'Unknown',
        'resolved': engineerResolved[eid] ?? 0,
        'rating': (eng['avg_rating'] as num?)?.toDouble() ?? 0.0,
        'total_resolved': (eng['total_resolved'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    _engineerStats.sort(
      (a, b) => (b['resolved'] as int).compareTo(a['resolved'] as int),
    );

    _computeVolumeTrend();
    _computeCustomerGrowth();
  }

  // ─── VOLUME TREND ─────────────────────────────────────────
  void _computeVolumeTrend() {
    _volumeLabels = [];
    _volumeValues = [];
    final now = DateTime.now();

    switch (_period) {
      case '7d':
        for (int i = 6; i >= 0; i--) {
          final date = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i));
          final count = _filteredTickets.where((t) {
            final d = DateTime.tryParse(t['created_at'] ?? '');
            return d != null &&
                d.year == date.year &&
                d.month == date.month &&
                d.day == date.day;
          }).length;
          _volumeLabels.add('${date.day}/${date.month}');
          _volumeValues.add(count.toDouble());
        }
        break;

      case '30d':
        for (int i = 5; i >= 0; i--) {
          final end = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i * 5));
          final start = end.subtract(const Duration(days: 5));
          final count = _filteredTickets.where((t) {
            final d = DateTime.tryParse(t['created_at'] ?? '');
            return d != null && d.isAfter(start) && !d.isAfter(end);
          }).length;
          _volumeLabels.add('${end.day}/${end.month}');
          _volumeValues.add(count.toDouble());
        }
        break;

      case '90d':
        for (int i = 6; i >= 0; i--) {
          final end = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i * 13));
          final start = end.subtract(const Duration(days: 13));
          final count = _filteredTickets.where((t) {
            final d = DateTime.tryParse(t['created_at'] ?? '');
            return d != null && d.isAfter(start) && !d.isAfter(end);
          }).length;
          _volumeLabels.add('${end.day}/${end.month}');
          _volumeValues.add(count.toDouble());
        }
        break;

      default: // all time — monthly buckets
        if (_allTickets.isEmpty) return;
        final oldest = DateTime.tryParse(
              _allTickets.first['created_at'] ?? '',
            ) ??
            now;
        var current = DateTime(oldest.year, oldest.month, 1);
        const months = [
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
          'Dec',
        ];
        while (current.isBefore(now)) {
          final monthEnd = DateTime(current.year, current.month + 1, 1);
          final count = _allTickets.where((t) {
            final d = DateTime.tryParse(t['created_at'] ?? '');
            return d != null && !d.isBefore(current) && d.isBefore(monthEnd);
          }).length;
          _volumeLabels.add(
            "${months[current.month - 1]} '${current.year % 100}",
          );
          _volumeValues.add(count.toDouble());
          current = monthEnd;
        }
    }
  }

  // ─── CUSTOMER GROWTH ──────────────────────────────────────
  void _computeCustomerGrowth() {
    _growthLabels = [];
    _growthValues = [];
    if (_customers.isEmpty) return;

    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort(
        (a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''),
      );

    final oldest =
        DateTime.tryParse(sorted.first['created_at'] ?? '') ?? DateTime.now();
    final now = DateTime.now();
    var current = DateTime(oldest.year, oldest.month, 1);
    int cumulative = 0;
    const months = [
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
      'Dec',
    ];

    // FIX: original had broken loop condition (missing parentheses)
    // Correct: continue while current month <= now month
    while (current.isBefore(DateTime(now.year, now.month + 1, 1))) {
      final monthEnd = DateTime(current.year, current.month + 1, 1);
      final monthCount = sorted.where((c) {
        final d = DateTime.tryParse(c['created_at'] ?? '');
        return d != null && !d.isBefore(current) && d.isBefore(monthEnd);
      }).length;
      cumulative += monthCount;
      _growthLabels.add(
        "${months[current.month - 1]} '${current.year % 100}",
      );
      _growthValues.add(cumulative.toDouble());
      current = monthEnd;
      if (_growthLabels.length > 24) break; // safety cap
    }
  }

  // ─── FORMATTERS ────────────────────────────────────────────
  String _formatHours(double hours) {
    if (hours < 1) return '${(hours * 60).toInt()}m';
    if (hours < 24) return '${hours.toStringAsFixed(1)}h';
    return '${(hours / 24).toStringAsFixed(1)}d';
  }

  String _formatMinutes(double minutes) {
    if (minutes < 60) return '${minutes.toInt()}m';
    if (minutes < 1440) {
      return '${(minutes / 60).toStringAsFixed(1)}h';
    }
    return '${(minutes / 1440).toStringAsFixed(1)}d';
  }

  String _formatStatus(String s) => s.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  double _yInterval(double maxVal) {
    if (maxVal <= 5) return 1;
    if (maxVal <= 10) return 2;
    if (maxVal <= 25) return 5;
    if (maxVal <= 50) return 10;
    if (maxVal <= 100) return 20;
    return (maxVal / 5).ceilToDouble();
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    IconData? icon,
    Color? color,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isError) ...[
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
            ] else if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? Colors.red.shade400 : (color ?? _primaryColor),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: _accentColor,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          const SizedBox(height: 16),
                          _buildPeriodSelector(),
                          const SizedBox(height: 16),
                          _buildSummaryCards(),
                          const SizedBox(height: 12),
                          _buildTypeBreakdown(),
                          const SizedBox(height: 20),
                          _buildChartCard(
                            title: 'Ticket Status Distribution',
                            subtitle: '$_totalCount total tickets',
                            height: 240,
                            child: _buildStatusPieChart(),
                          ),
                          _buildChartCard(
                            title: 'Ticket Volume Trend',
                            subtitle: 'Tickets created over time',
                            height: 220,
                            child: _buildVolumeTrendChart(),
                          ),
                          _buildChartCard(
                            title: 'Priority Distribution',
                            subtitle: 'Tickets by priority level',
                            height: 200,
                            child: _buildPriorityBarChart(),
                          ),
                          _buildChartCard(
                            title: 'Engineer Performance',
                            subtitle: 'Resolved tickets in period',
                            height: null,
                            child: _buildEngineerPerformance(),
                          ),
                          _buildChartCard(
                            title: 'Machine Categories',
                            subtitle: 'Tickets by machine category',
                            height: 240,
                            child: _buildCategoryPieChart(),
                          ),
                          _buildChartCard(
                            title: 'Customer Growth',
                            subtitle: 'Cumulative registrations (all time)',
                            height: 220,
                            child: _buildCustomerGrowthChart(),
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

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _primaryColor,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  'Performance insights & trends',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: _softShadow,
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: _primaryColor,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PERIOD SELECTOR ───────────────────────────────────────
  Widget _buildPeriodSelector() {
    final periods = ['7d', '30d', '90d', 'All'];

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: Row(
        children: periods.map((p) {
          final key = p.toLowerCase();
          final isSelected = _period == key;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _period = key;
                  _computeAnalytics();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : _textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── SUMMARY CARDS ─────────────────────────────────────────
  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatCard(
                icon: Icons.confirmation_number_rounded,
                label: 'Total Tickets',
                value: '$_totalCount',
                color: _primaryColor,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                icon: Icons.timer_rounded,
                label: 'Avg Resolution',
                value: _avgResolutionHours > 0
                    ? _formatHours(_avgResolutionHours)
                    : '—',
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                icon: Icons.star_rounded,
                label: 'Satisfaction',
                value: _ratingCount > 0 ? _avgRating.toStringAsFixed(1) : '—',
                color: const Color(0xFFF59E0B),
                suffix: _ratingCount > 0 ? '/5' : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.flash_on_rounded,
                label: 'First Response',
                value: _avgResponseMinutes > 0
                    ? _formatMinutes(_avgResponseMinutes)
                    : '—',
                color: const Color(0xFF06B6D4),
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                icon: Icons.check_circle_rounded,
                label: 'Resolution Rate',
                value: _totalCount > 0
                    ? '${_resolutionRate.toStringAsFixed(0)}%'
                    : '—',
                color: _accentColor,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                icon: Icons.priority_high_rounded,
                label: 'Escalation',
                value: _totalCount > 0
                    ? '${_escalationRate.toStringAsFixed(0)}%'
                    : '—',
                color: const Color(0xFFEF4444),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? suffix,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: _isDark ? Border.all(color: _borderColor) : null,
          boxShadow: _cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (suffix != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 2,
                      bottom: 2,
                    ),
                    child: Text(
                      suffix,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: _textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── TYPE BREAKDOWN ────────────────────────────────────────
  Widget _buildTypeBreakdown() {
    final types = [
      {
        'key': 'support',
        'label': 'Support',
        'icon': Icons.support_agent_rounded,
        'color': _primaryColor,
      },
      {
        'key': 'order',
        'label': 'Orders',
        'icon': Icons.shopping_cart_rounded,
        'color': _accentColor,
      },
      {
        'key': 'inquiry',
        'label': 'Inquiries',
        'icon': Icons.help_outline_rounded,
        'color': const Color(0xFFF59E0B),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: types.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          final count = _typeCounts[t['key']] ?? 0;
          final color = t['color'] as Color;
          // FIX: replaced .withOpacity() with .withAlpha()
          final bgAlpha = _isDark ? 20 : 15; // ~8% and ~6%
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 10 : 0),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: color.withAlpha(bgAlpha),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withAlpha(38),
                ),
              ),
              child: Row(
                children: [
                  t['key'] == 'support'
                      ? IcChatGearIcon(size: 16, color: color)
                      : Icon(
                          t['icon'] as IconData,
                          size: 16,
                          color: color,
                        ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Text(
                          t['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── CHART CARD WRAPPER ────────────────────────────────────
  Widget _buildChartCard({
    required String title,
    String? subtitle,
    required double? height,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
            ),
          const SizedBox(height: 20),
          height != null ? SizedBox(height: height, child: child) : child,
        ],
      ),
    );
  }

  // ─── STATUS PIE CHART ──────────────────────────────────────
  Widget _buildStatusPieChart() {
    final hasData = _statusCounts.values.any((v) => v > 0);
    if (!hasData) {
      return _buildEmptyChart('No ticket data for this period');
    }

    final entries = _statusCounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Row(
      children: [
        // Pie chart
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      _touchedStatusIndex = -1;
                      return;
                    }
                    _touchedStatusIndex =
                        pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: List.generate(entries.length, (i) {
                final e = entries[i];
                final isTouched = i == _touchedStatusIndex;
                final pct = (_totalCount > 0 ? e.value / _totalCount * 100 : 0)
                    .toStringAsFixed(0);
                return PieChartSectionData(
                  value: e.value.toDouble(),
                  title: isTouched ? '$pct%' : '',
                  color: _statusColors[e.key] ?? Colors.grey,
                  radius: isTouched ? 70 : 60,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Legend
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.map((e) {
              return _buildLegendItem(
                color: _statusColors[e.key] ?? Colors.grey,
                label: _formatStatus(e.key),
                value: '${e.value}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── VOLUME TREND LINE CHART ───────────────────────────────
  Widget _buildVolumeTrendChart() {
    if (_volumeValues.isEmpty || _volumeValues.every((v) => v == 0)) {
      return _buildEmptyChart('No volume data for this period');
    }

    final spots = List.generate(
      _volumeValues.length,
      (i) => FlSpot(i.toDouble(), _volumeValues[i]),
    );
    final maxY = _volumeValues.fold<double>(
      0,
      (a, b) => b > a ? b : a,
    );
    final chartMaxY = maxY > 0 ? maxY * 1.25 : 10;
    final interval = _yInterval(maxY);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: _gridColor, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _volumeLabels.length) {
                  return const SizedBox.shrink();
                }
                if (_volumeLabels.length > 8 && idx % 2 != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _volumeLabels[idx],
                    style: TextStyle(
                      fontSize: 11,
                      color: _textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: _dividerColor,
              width: 1,
            ),
          ),
        ),
        minY: 0,
        maxY: chartMaxY.toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: _primaryColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 4,
                color: _primaryColor,
                strokeWidth: 2,
                strokeColor: _cardBg,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              // FIX: replaced .withOpacity() with .withAlpha()
              // 0.08 ≈ 20 alpha, 0.12 ≈ 31 alpha
              color: _primaryColor.withAlpha(_isDark ? 20 : 31),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final idx = spot.x.toInt();
              final label = idx >= 0 && idx < _volumeLabels.length
                  ? _volumeLabels[idx]
                  : '';
              return LineTooltipItem(
                '$label\n${spot.y.toInt()} tickets',
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ─── PRIORITY BAR CHART ────────────────────────────────────
  Widget _buildPriorityBarChart() {
    final priorities = ['urgent', 'high', 'medium', 'low'];
    final labels = ['Urgent', 'High', 'Medium', 'Low'];
    final colors = [
      _priorityColors['urgent']!,
      _priorityColors['high']!,
      _priorityColors['medium']!,
      _priorityColors['low']!,
    ];

    final values =
        priorities.map((p) => (_priorityCounts[p] ?? 0).toDouble()).toList();
    final maxVal = values.fold<double>(0, (a, b) => b > a ? b : a);

    if (maxVal == 0) {
      return _buildEmptyChart('No priority data');
    }

    final chartMaxY = maxVal * 1.25;
    final interval = _yInterval(maxVal);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMaxY,
        barGroups: List.generate(4, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                color: colors[i],
                width: 28,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: chartMaxY,
                  color: _barBg,
                ),
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: _gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[idx],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors[idx],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg,
            getTooltipItem: (group, _, rod, __) {
              final idx = group.x.toInt();
              return BarTooltipItem(
                '${labels[idx]}: ${rod.toY.toInt()}',
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colors[idx],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── ENGINEER PERFORMANCE ──────────────────────────────────
  Widget _buildEngineerPerformance() {
    final top = _engineerStats.take(8).toList();
    if (top.isEmpty) {
      return _buildEmptyChart('No engineer data');
    }

    final maxResolved = top.fold<int>(
      0,
      (a, e) => (e['resolved'] as int) > a ? (e['resolved'] as int) : a,
    );

    return Column(
      children: top.asMap().entries.map((entry) {
        final i = entry.key;
        final eng = entry.value;
        final resolved = eng['resolved'] as int;
        final rating = eng['rating'] as double;
        final progress = maxResolved > 0 ? resolved / maxResolved : 0.0;

        return Padding(
          padding: EdgeInsets.only(
            bottom: i < top.length - 1 ? 14 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _primaryColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      eng['name'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rating > 0) ...[
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$resolved',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: _barBg,
                  valueColor: AlwaysStoppedAnimation(
                    Color.lerp(
                          _accentColor,
                          _primaryColor,
                          progress,
                        ) ??
                        _primaryColor,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── CATEGORY PIE CHART ────────────────────────────────────
  Widget _buildCategoryPieChart() {
    final hasData = _categoryCounts.values.any((v) => v > 0);
    if (!hasData) {
      return _buildEmptyChart('No machine category data');
    }

    final entries = _categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, b) => a + b.value);

    return Row(
      children: [
        // Pie chart
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      _touchedCategoryIndex = -1;
                      return;
                    }
                    _touchedCategoryIndex =
                        pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: List.generate(entries.length, (i) {
                final e = entries[i];
                final isTouched = i == _touchedCategoryIndex;
                final pct =
                    (total > 0 ? e.value / total * 100 : 0).toStringAsFixed(0);
                final color = _categoryPalette[i % _categoryPalette.length];
                return PieChartSectionData(
                  value: e.value.toDouble(),
                  title: isTouched ? '$pct%' : '',
                  color: color,
                  radius: isTouched ? 70 : 60,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Legend
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              return _buildLegendItem(
                color: _categoryPalette[i % _categoryPalette.length],
                label: e.key,
                value: '${e.value}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── CUSTOMER GROWTH LINE CHART ────────────────────────────
  Widget _buildCustomerGrowthChart() {
    if (_growthValues.isEmpty) {
      return _buildEmptyChart('No customer data');
    }

    final spots = List.generate(
      _growthValues.length,
      (i) => FlSpot(i.toDouble(), _growthValues[i]),
    );
    final maxY = _growthValues.fold<double>(
      0,
      (a, b) => b > a ? b : a,
    );
    final chartMaxY = maxY > 0 ? maxY * 1.15 : 10;
    final interval = _yInterval(maxY);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: _gridColor, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _growthLabels.length) {
                  return const SizedBox.shrink();
                }
                // Show every Nth label to avoid crowding
                final step = (_growthLabels.length / 6).ceil().clamp(1, 100);
                if (idx % step != 0 && idx != _growthLabels.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _growthLabels[idx],
                    style: TextStyle(
                      fontSize: 11,
                      color: _textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: _dividerColor,
              width: 1,
            ),
          ),
        ),
        minY: 0,
        maxY: chartMaxY.toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: _accentColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: _growthValues.length <= 12,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: _accentColor,
                strokeWidth: 2,
                strokeColor: _cardBg,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              // FIX: replaced .withOpacity() with .withAlpha()
              // 0.08 ≈ 20 alpha, 0.12 ≈ 31 alpha
              color: _accentColor.withAlpha(_isDark ? 20 : 31),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final idx = spot.x.toInt();
              final label = idx >= 0 && idx < _growthLabels.length
                  ? _growthLabels[idx]
                  : '';
              return LineTooltipItem(
                '$label\n${spot.y.toInt()} customers',
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ─── LEGEND ITEM ───────────────────────────────────────────
  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY CHART STATE ─────────────────────────────────────
  Widget _buildEmptyChart(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 40,
              color: _textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: _textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOADING STATE (Shimmer) ───────────────────────────────
  Widget _buildLoadingState() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Period selector shimmer
        _shimmerBox(height: 44, radius: 14),
        const SizedBox(height: 16),
        // Stat cards row 1
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
          ],
        ),
        const SizedBox(height: 10),
        // Stat cards row 2
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90, radius: 16)),
          ],
        ),
        const SizedBox(height: 12),
        // Type breakdown
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 54, radius: 12)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 54, radius: 12)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 54, radius: 12)),
          ],
        ),
        const SizedBox(height: 20),
        // Chart cards
        _shimmerBox(height: 300, radius: 20),
        const SizedBox(height: 16),
        _shimmerBox(height: 280, radius: 20),
        const SizedBox(height: 16),
        _shimmerBox(height: 260, radius: 20),
      ],
    );
  }

  Widget _shimmerBox({
    required double height,
    required double radius,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _isDark ? Brand.darkCardElevated : const Color(0xFFEEF0F5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
