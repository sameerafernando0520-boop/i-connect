// lib/screens/marketing/ma_analytics_page.dart
// P7 — Analytics: article views + bookmarks overview with fl_chart charts

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _anColor = AdminColors.primary; // analytics accent

class MaAnalyticsPage extends StatefulWidget {
  const MaAnalyticsPage({super.key});

  @override
  State<MaAnalyticsPage> createState() => _MaAnalyticsPageState();
}

class _MaAnalyticsPageState extends State<MaAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── Article Views state ──
  List<Map<String, dynamic>> _topArticles = [];
  int _totalViews = 0;
  int _uniqueReaders = 0;
  Map<String, int> _viewsByCategory = {};
  bool _loadingViews = true;
  String? _viewsError;

  // ── Bookmarks state ──
  List<Map<String, dynamic>> _topBookmarked = [];
  int _totalBookmarks = 0;
  bool _loadingBookmarks = true;
  String? _bookmarksError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadViews();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ─── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadViews() async {
    setState(() { _loadingViews = true; _viewsError = null; });
    try {
      // article_views is an EVENT LOG (one row per view), not a counter table.
      // We aggregate count(*) per article in Dart, and count distinct user_ids
      // for unique readers.
      final res = await SupabaseConfig.client
          .from('article_views')
          .select(
            'article_id, user_id, '
            'article:knowledge_base!article_id(id, title, category, is_published)',
          );
      if (!mounted) return;

      final list = List<Map<String, dynamic>>.from(res);

      // Aggregate by article
      final Map<String, Map<String, dynamic>> byArticle = {};
      int totalViews = 0;
      final Set<String> uniqueReaders = {};

      for (final row in list) {
        final articleId = row['article_id'] as String? ?? '';
        final userId = row['user_id'] as String?;
        final article = row['article'] as Map<String, dynamic>?;
        if (article == null) continue;

        totalViews += 1; // one row = one view event
        if (userId != null) uniqueReaders.add(userId);

        if (!byArticle.containsKey(articleId)) {
          byArticle[articleId] = {
            'article_id': articleId,
            'title': article['title'] ?? 'Untitled',
            'category': article['category'] ?? '',
            'is_published': article['is_published'] ?? false,
            'total_views': 0,
          };
        }
        byArticle[articleId]!['total_views'] =
            (byArticle[articleId]!['total_views'] as int) + 1;
      }

      // Sort by views desc, take top 10
      final sorted = byArticle.values.toList()
        ..sort((a, b) => (b['total_views'] as int).compareTo(a['total_views'] as int));
      final top10 = sorted.take(10).toList();

      // Views by category
      final Map<String, int> byCat = {};
      for (final a in byArticle.values) {
        final cat = (a['category'] as String).isEmpty ? 'Uncategorized' : a['category'] as String;
        byCat[cat] = (byCat[cat] ?? 0) + (a['total_views'] as int);
      }

      if (!mounted) return;
      setState(() {
        _topArticles = top10;
        _totalViews = totalViews;
        _uniqueReaders = uniqueReaders.length;
        _viewsByCategory = byCat;
        _loadingViews = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _viewsError = e.toString(); _loadingViews = false; });
    }
  }

  Future<void> _loadBookmarks() async {
    setState(() { _loadingBookmarks = true; _bookmarksError = null; });
    try {
      final res = await SupabaseConfig.client
          .from('user_bookmarks')
          .select('article_id, article:knowledge_base!article_id(id, title, category)');
      if (!mounted) return;

      final list = List<Map<String, dynamic>>.from(res);

      final Map<String, Map<String, dynamic>> byArticle = {};
      for (final row in list) {
        final articleId = row['article_id'] as String? ?? '';
        final article = row['article'] as Map<String, dynamic>?;
        if (article == null) continue;

        if (!byArticle.containsKey(articleId)) {
          byArticle[articleId] = {
            'article_id': articleId,
            'title': article['title'] ?? 'Untitled',
            'category': article['category'] ?? '',
            'count': 0,
          };
        }
        byArticle[articleId]!['count'] =
            (byArticle[articleId]!['count'] as int) + 1;
      }

      final sorted = byArticle.values.toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      if (!mounted) return;
      setState(() {
        _topBookmarked = sorted.take(10).toList();
        _totalBookmarks = list.length;
        _loadingBookmarks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _bookmarksError = e.toString(); _loadingBookmarks = false; });
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Analytics',
        accent: HeroAccent.violet,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () { _loadViews(); _loadBookmarks(); },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(153),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Article Views'),
            Tab(text: 'Bookmarks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildViewsTab(isDark),
          _buildBookmarksTab(isDark),
        ],
      ),
    );
  }

  // ─── Views Tab ───────────────────────────────────────────────────────────────

  Widget _buildViewsTab(bool isDark) {
    if (_loadingViews) {
      return const Center(child: CircularProgressIndicator(color: _anColor));
    }
    if (_viewsError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AdminColors.error.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, size: 32, color: StatusColors.danger),
          ),
          const SizedBox(height: 16),
          Text('Failed to load views',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          const SizedBox(height: 8),
          Text(_viewsError!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadViews,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(backgroundColor: _anColor),
          ),
        ]),
      ));
    }

    return RefreshIndicator(
      onRefresh: _loadViews,
      color: _anColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── Summary KPI cards ──
          Row(children: [
            Expanded(child: _kpiCard('Total Views', _totalViews.toString(),
                Icons.visibility_rounded, _anColor, isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Articles Read', _uniqueReaders.toString(),
                Icons.menu_book_rounded, Brand.lightGreen, isDark)),
          ]),
          const SizedBox(height: 20),
          // ── Views by category bar chart ──
          if (_viewsByCategory.isNotEmpty) ...[
            _sectionLabel('Views by Category', isDark),
            const SizedBox(height: 12),
            _categoryBarChart(isDark),
            const SizedBox(height: 24),
          ],
          // ── Top articles ──
          _sectionLabel('Top ${_topArticles.length} Articles by Views', isDark),
          const SizedBox(height: 12),
          if (_topArticles.isEmpty)
            _emptyState('No article view data yet', Icons.menu_book_outlined)
          else
            ..._topArticles.asMap().entries.map(
                (e) => _articleViewCard(e.key + 1, e.value, isDark)),
        ],
      ),
    );
  }

  Widget _categoryBarChart(bool isDark) {
    final entries = _viewsByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top6 = entries.take(6).toList();
    final maxVal = top6.isEmpty ? 1 : top6.first.value.toDouble();

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = top6[group.x].key;
                return BarTooltipItem(
                  '$label\n${rod.toY.toInt()} views',
                  const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= top6.length) return const SizedBox();
                  final cat = top6[idx].key;
                  final label = cat.length > 8 ? '${cat.substring(0, 7)}…' : cat;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context))),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(
                      fontSize: 11, color: AdminColors.textHint(context)),
                ),
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxVal / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: (isDark ? Brand.darkBorder : Brand.borderLight),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: top6.asMap().entries.map((e) {
            final colors = [
              _anColor,
              Brand.lightGreen,
              AdminColors.warning,
              AdminColors.error,
              AdminColors.accent,
              AdminColors.internal,
            ];
            final color = colors[e.key % colors.length];
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value.toDouble(),
                  color: color,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _articleViewCard(int rank, Map<String, dynamic> a, bool isDark) {
    final title = a['title'] as String? ?? 'Untitled';
    final category = a['category'] as String? ?? '';
    final views = a['total_views'] as int? ?? 0;
    final isPublished = a['is_published'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        // Rank badge
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _anColor.withAlpha(rank <= 3 ? 40 : 20),
            borderRadius: BorderRadius.circular(Brand.r(8)),
          ),
          child: Center(
            child: Text('#$rank',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? _anColor : AdminColors.textHint(context))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            if (category.isNotEmpty)
              Text(category,
                  style: TextStyle(
                      fontSize: 11, color: AdminColors.textHint(context))),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            Icon(Icons.visibility_rounded, size: 13,
                color: AdminColors.textHint(context)),
            const SizedBox(width: 3),
            Text('$views',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : Brand.royalBlueDark)),
          ]),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (isPublished ? AdminColors.success : AdminColors.warning)
                  .withAlpha(20),
              borderRadius: BorderRadius.circular(Brand.r(4)),
            ),
            child: Text(
              isPublished ? 'Published' : 'Draft',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isPublished
                      ? AdminColors.success
                      : AdminColors.warning),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── Bookmarks Tab ───────────────────────────────────────────────────────────

  Widget _buildBookmarksTab(bool isDark) {
    if (_loadingBookmarks) {
      return const Center(child: CircularProgressIndicator(color: _anColor));
    }
    if (_bookmarksError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AdminColors.error.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, size: 32, color: StatusColors.danger),
          ),
          const SizedBox(height: 16),
          Text('Failed to load bookmarks',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          const SizedBox(height: 8),
          Text(_bookmarksError!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadBookmarks,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(backgroundColor: _anColor),
          ),
        ]),
      ));
    }

    return RefreshIndicator(
      onRefresh: _loadBookmarks,
      color: _anColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── KPI ──
          Row(children: [
            Expanded(child: _kpiCard('Total Bookmarks', _totalBookmarks.toString(),
                Icons.bookmark_rounded, _anColor, isDark)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Articles Saved', _topBookmarked.length.toString(),
                Icons.library_books_rounded, Brand.lightGreen, isDark)),
          ]),
          const SizedBox(height: 20),
          // ── Pie chart ──
          if (_topBookmarked.isNotEmpty) ...[
            _sectionLabel('Bookmark Distribution', isDark),
            const SizedBox(height: 12),
            _bookmarkPieChart(isDark),
            const SizedBox(height: 24),
          ],
          // ── Top list ──
          _sectionLabel('Most Bookmarked Articles', isDark),
          const SizedBox(height: 12),
          if (_topBookmarked.isEmpty)
            _emptyState('No bookmark data yet', Icons.bookmark_border_rounded)
          else
            ..._topBookmarked.asMap().entries.map(
                (e) => _bookmarkCard(e.key + 1, e.value, isDark)),
        ],
      ),
    );
  }

  Widget _bookmarkPieChart(bool isDark) {
    final top5 = _topBookmarked.take(5).toList();
    final totalShown = top5.fold<int>(0, (s, a) => s + (a['count'] as int));
    final colors = [
      _anColor,
      Brand.lightGreen,
      AdminColors.warning,
      AdminColors.error,
      AdminColors.accent,
    ];

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: top5.asMap().entries.map((e) {
                final pct = totalShown == 0
                    ? 0.0
                    : (e.value['count'] as int) / totalShown * 100;
                return PieChartSectionData(
                  color: colors[e.key % colors.length],
                  value: e.value['count'].toDouble(),
                  title: '${pct.toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                  radius: 50,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Legend
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: top5.asMap().entries.map((e) {
            final title = (e.value['title'] as String? ?? 'Untitled');
            final label = title.length > 16 ? '${title.substring(0, 15)}…' : title;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: colors[e.key % colors.length],
                    borderRadius: BorderRadius.circular(Brand.r(3)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.textSub(context))),
              ]),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _bookmarkCard(int rank, Map<String, dynamic> a, bool isDark) {
    final title = a['title'] as String? ?? 'Untitled';
    final category = a['category'] as String? ?? '';
    final count = a['count'] as int? ?? 0;
    final maxCount = _topBookmarked.isNotEmpty
        ? (_topBookmarked.first['count'] as int? ?? 1)
        : 1;
    final pct = maxCount == 0 ? 0.0 : count / maxCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: _anColor.withAlpha(rank <= 3 ? 40 : 20),
              borderRadius: BorderRadius.circular(Brand.r(7)),
            ),
            child: Center(
              child: Text('#$rank',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: rank <= 3 ? _anColor : AdminColors.textHint(context))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              if (category.isNotEmpty)
                Text(category,
                    style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.textHint(context))),
            ]),
          ),
          const SizedBox(width: 8),
          Row(children: [
            Icon(Icons.bookmark_rounded, size: 14, color: _anColor),
            const SizedBox(width: 3),
            Text('$count',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : Brand.royalBlueDark)),
          ]),
        ]),
        const SizedBox(height: 8),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(Brand.r(4)),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 4,
            backgroundColor: isDark ? Brand.darkBorder : Brand.borderLight,
            valueColor: const AlwaysStoppedAnimation<Color>(_anColor),
          ),
        ),
      ]),
    );
  }

  // ─── Shared helpers ──────────────────────────────────────────────────────────

  Widget _kpiCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ]),
        const SizedBox(height: 12),
        Text(value,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
      ]),
    );
  }

  Widget _sectionLabel(String text, bool isDark) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
      );

  Widget _emptyState(String msg, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _anColor.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: _anColor),
          ),
          const SizedBox(height: 16),
          Text(msg,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        ]),
      ),
    );
  }
}
