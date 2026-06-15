// lib/screens/customer/knowledge_base_page.dart

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../utils/time_utils.dart';
import '../../services/points_service.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';
import 'article_detail_page.dart';
import '../../widgets/ds/ds_widgets.dart';

class KnowledgeBasePage extends StatefulWidget {
  final String? initialCategory;
  final String? machineCategory;
  final bool showNavBar;

  const KnowledgeBasePage({
    super.key,
    this.initialCategory,
    this.machineCategory,
    this.showNavBar = true,
  });

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _filteredArticles = [];
  List<Map<String, dynamic>> _recentlyViewed = [];
  Set<String> _bookmarkedIds = {};
  List<String> _userMachineCategories = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _selectedContentType = 'all';
  String _selectedMachineCategory = 'all';
  String _sortBy = 'newest';
  final _searchController = TextEditingController();
  bool _isSearchExpanded = false;
  Timer? _debounceTimer;
  String? _currentUserId;

  static const int _pageSize = 20;
  int _currentPage = 0;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _contentTypes = [
    {'value': 'all', 'label': 'All', 'icon': Icons.apps_rounded},
    {'value': 'manual', 'label': 'Manuals', 'icon': Icons.menu_book_rounded},
    {'value': 'video', 'label': 'Videos', 'icon': Icons.play_circle_rounded},
    {
      'value': 'troubleshooting',
      'label': 'Fixes',
      'icon': Icons.build_circle_rounded
    },
    {'value': 'faq', 'label': 'FAQs', 'icon': Icons.help_rounded},
    {'value': 'guide', 'label': 'Guides', 'icon': Icons.assignment_rounded},
  ];

  final List<Map<String, dynamic>> _machineCategories = [
    {'value': 'all', 'label': 'All Machines', 'icon': Icons.devices_rounded},
    {
      'value': 'Digital Printers',
      'label': 'Printers',
      'icon': Icons.print_rounded
    },
    {
      'value': 'CNC Routers',
      'label': 'CNC',
      'icon': Icons.precision_manufacturing_rounded
    },
    {
      'value': 'Laser Cutters',
      'label': 'Laser',
      'icon': Icons.content_cut_rounded
    },
    {
      'value': 'Finishing Equipment',
      'label': 'Finishing',
      'icon': Icons.construction_rounded
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (widget.initialCategory != null) {
      _selectedContentType = widget.initialCategory!;
    }
    if (widget.machineCategory != null) {
      _selectedMachineCategory = widget.machineCategory!;
    }
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreArticles();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait<dynamic>([
      _loadArticles(reset: true),
      _loadRecentlyViewed(),
      _loadBookmarks(),
      _loadUserMachineCategories(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadArticles({bool reset = false}) async {
    if (reset) {
      _currentPage = 0;
      _hasMore = true;
    }

    try {
      var filterQuery = SupabaseConfig.client
          .from('knowledge_base')
          .select('*')
          .eq('is_published', true);

      if (_selectedMachineCategory != 'all') {
        filterQuery =
            filterQuery.eq('machine_category', _selectedMachineCategory);
      }

      if (_selectedContentType != 'all') {
        filterQuery = filterQuery.eq('content_type', _selectedContentType);
      }

      late final List<Map<String, dynamic>> data;

      switch (_sortBy) {
        case 'popular':
          data = await filterQuery.order('views', ascending: false).range(
                _currentPage * _pageSize,
                (_currentPage + 1) * _pageSize - 1,
              );
          break;
        case 'oldest':
          data = await filterQuery.order('created_at', ascending: true).range(
                _currentPage * _pageSize,
                (_currentPage + 1) * _pageSize - 1,
              );
          break;
        default:
          data = await filterQuery.order('created_at', ascending: false).range(
                _currentPage * _pageSize,
                (_currentPage + 1) * _pageSize - 1,
              );
      }

      final articles = List<Map<String, dynamic>>.from(data);

      if (mounted) {
        setState(() {
          if (reset) {
            _articles = articles;
          } else {
            _articles.addAll(articles);
          }
          _hasMore = articles.length >= _pageSize;
          _applyLocalFilters();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to load articles');
        debugPrint('Error loading articles: $e');
      }
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    await _loadArticles();
    if (mounted) setState(() => _isLoadingMore = false);
  }

  Future<void> _loadRecentlyViewed() async {
    if (_currentUserId == null) return;
    try {
      final data = await SupabaseConfig.client
          .from('article_views')
          .select(
              'article_id, viewed_at, knowledge_base!inner(id, title, content_type, machine_category, views, thumbnail_url, tags)')
          .eq('user_id', _currentUserId!)
          .order('viewed_at', ascending: false)
          .limit(5);

      if (!mounted) return;
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final item in data) {
        final articleId = item['article_id']?.toString() ?? '';
        if (!seen.contains(articleId)) {
          seen.add(articleId);
          unique.add({
            ...item['knowledge_base'] as Map<String, dynamic>,
            'viewed_at': item['viewed_at'],
          });
        }
      }
      setState(() => _recentlyViewed = unique);
    } catch (e) {
      debugPrint('⚠️ Recently viewed not available: $e');
    }
  }

  Future<void> _loadBookmarks() async {
    if (_currentUserId == null) return;
    try {
      final data = await SupabaseConfig.client
          .from('user_bookmarks')
          .select('article_id')
          .eq('user_id', _currentUserId!);

      if (!mounted) return;
      setState(() {
        _bookmarkedIds =
            data.map<String>((b) => b['article_id'].toString()).toSet();
      });
    } catch (e) {
      debugPrint('⚠️ Bookmarks not available: $e');
    }
  }

  Future<void> _loadUserMachineCategories() async {
    if (_currentUserId == null) return;
    try {
      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('machine_catalog!inner(category)')
          .eq('user_id', _currentUserId!);

      if (!mounted) return;
      final categories = data
          .map<String>((m) =>
              (m['machine_catalog'] as Map<String, dynamic>)['category']
                  ?.toString() ??
              '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      setState(() => _userMachineCategories = categories);
    } catch (e) {
      debugPrint('Error loading user machine categories: $e');
    }
  }

  Future<void> _toggleBookmark(String articleId) async {
    if (_currentUserId == null) return;

    final isBookmarked = _bookmarkedIds.contains(articleId);

    setState(() {
      if (isBookmarked) {
        _bookmarkedIds.remove(articleId);
      } else {
        _bookmarkedIds.add(articleId);
      }
    });

    try {
      if (isBookmarked) {
        await SupabaseConfig.client
            .from('user_bookmarks')
            .delete()
            .eq('user_id', _currentUserId!)
            .eq('article_id', articleId);
      } else {
        await SupabaseConfig.client.from('user_bookmarks').insert({
          'user_id': _currentUserId,
          'article_id': articleId,
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isBookmarked) {
          _bookmarkedIds.add(articleId);
        } else {
          _bookmarkedIds.remove(articleId);
        }
      });
      debugPrint('Error toggling bookmark: $e');
    }
  }

  void _applyLocalFilters() {
    var filtered = List<Map<String, dynamic>>.from(_articles);

    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((a) {
        final title = (a['title'] ?? '').toString().toLowerCase();
        final content = (a['content'] ?? '').toString().toLowerCase();
        final category = (a['category'] ?? '').toString().toLowerCase();
        final machineCategory =
            (a['machine_category'] ?? '').toString().toLowerCase();
        final tags = (a['tags'] as List?)?.join(' ').toLowerCase() ?? '';
        return title.contains(query) ||
            content.contains(query) ||
            category.contains(query) ||
            machineCategory.contains(query) ||
            tags.contains(query);
      }).toList();
    }

    _filteredArticles = filtered;
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _applyLocalFilters());
    });
  }

  void _onFilterChanged() {
    _loadArticles(reset: true);
  }

  // ─── HELPERS ───────────────────────────────────────────────

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'manual':
        return Icons.menu_book_rounded;
      case 'video':
        return Icons.play_circle_rounded;
      case 'troubleshooting':
        return Icons.build_circle_rounded;
      case 'faq':
        return Icons.help_rounded;
      case 'guide':
        return Icons.assignment_rounded;
      default:
        return Icons.article_rounded;
    }
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'manual':
        return Brand.royalBlueDark;
      case 'video':
        return const Color(0xFFE53935);
      case 'troubleshooting':
        return const Color(0xFFFF9800);
      case 'faq':
        return Brand.lightGreen;
      case 'guide':
        return Brand.royalBlueLight;
      default:
        return Colors.grey;
    }
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'manual':
        return 'Manual';
      case 'video':
        return 'Video';
      case 'troubleshooting':
        return 'Fix';
      case 'faq':
        return 'FAQ';
      case 'guide':
        return 'Guide';
      default:
        return 'Article';
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
      margin: const EdgeInsets.all(16),
    ));
  }

  // FIX #5: Replace non-existent RPC with direct upsert (trigger handles views count)
  void _openArticle(Map<String, dynamic> article) {
    if (_currentUserId != null && article['id'] != null) {
      SupabaseConfig.client
          .from('article_views')
          .upsert(
            {
              'user_id': _currentUserId,
              'article_id': article['id'],
              'viewed_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id,article_id',
          )
          .then((_) {})
          .catchError((e) { debugPrint('⚠️ View tracking error: $e'); return null; });
    }

    // ── Award article read points (max 5/day) ──
    final articleId = article['id'] as String?;
    if (articleId != null) {
      PointsService.articleRead(articleId);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleDetailPage(articleId: article['id']),
      ),
    ).then((_) {
      if (!mounted) return;
      _loadRecentlyViewed();
      _loadArticles(reset: true);
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Navy Glow hero band sits behind the status bar in both modes.
      value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor:
              Brand.canvas(isDark)),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: Stack(
          children: [
            Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.2),
                  radius: 1.6,
                  colors: [
                    Brand.splashNavyGlow,
                    Brand.splashNavyCore,
                    Brand.splashNavyEdge,
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(isDark),
                  _buildStatsCard(isDark),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: Brand.canvas(isDark),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildContentTypeFilter(isDark),
                          if (_userMachineCategories.isNotEmpty ||
                              _selectedMachineCategory != 'all')
                            _buildMachineCategoryFilter(isDark),
                          _buildSearchBar(isDark),
                          _buildResultHeader(isDark),
                          Expanded(
                            child: _isLoading
                                ? _buildSkeletonLoading(isDark)
                                : _filteredArticles.isEmpty
                                    ? _buildEmptyState(isDark)
                                    : _buildArticlesList(isDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: widget.showNavBar
            ? CustomerNavBar(
                currentIndex: 3,
                onTabSelected: CustomerNavController.switchTab,
              )
            : null,
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(((isDark ? 0.08 : 0.15) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  border: Border.all(color: Colors.white.withAlpha(((0.1) * 255).toInt())),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guides, manuals & troubleshooting',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.3,
                        color: const Color(0xFF8FA3C8),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                const Text('Knowledge Base',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2)),
                const SizedBox(height: 6),
                const DsLimeLine(),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showBookmarkedArticles(isDark),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(((isDark ? 0.08 : 0.15) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  border: Border.all(color: Colors.white.withAlpha(((0.1) * 255).toInt())),
                ),
                child: Stack(
                  children: [
                    const Center(
                        child: Icon(Icons.bookmark_rounded,
                            color: Colors.white, size: 22)),
                    if (_bookmarkedIds.isNotEmpty)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Brand.lightGreen,
                              Brand.lightGreenBright
                            ]),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isDark
                                    ? Brand.darkCard
                                    : Brand.royalBlueDark,
                                width: 2),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Center(
                            child: Text('${_bookmarkedIds.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  setState(() => _isSearchExpanded = !_isSearchExpanded),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(((isDark ? 0.08 : 0.15) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  border: Border.all(color: Colors.white.withAlpha(((0.1) * 255).toInt())),
                ),
                child: Icon(
                    _isSearchExpanded
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    color: Colors.white,
                    size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATS CARD ────────────────────────────────────────────

  Widget _buildStatsCard(bool isDark) {
    final totalViews =
        _articles.fold<int>(0, (sum, a) => sum + ((a['views'] ?? 0) as int));
    final videoCount =
        _articles.where((a) => a['content_type'] == 'video').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(22)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(38),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
              Icons.article_rounded,
              '${_articles.length}',
              'Articles',
              isDark ? Brand.royalBlueGlow : Brand.royalBlue,
              isDark),
          _buildStatDivider(isDark),
          _buildStatItem(Icons.play_circle_rounded, '$videoCount', 'Videos',
              const Color(0xFFE53935), isDark),
          _buildStatDivider(isDark),
          _buildStatItem(Icons.visibility_rounded, '$totalViews', 'Views',
              isDark ? Brand.royalBlueGlow : Brand.royalBlueLight, isDark),
          _buildStatDivider(isDark),
          _buildStatItem(Icons.bookmark_rounded, '${_bookmarkedIds.length}',
              'Saved', Colors.amber, isDark),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String value, String label, Color color, bool isDark) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: isDark ? color.withAlpha(220) : color,
              letterSpacing: -0.3,
              height: 1)),
      const SizedBox(height: 4),
      Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4)),
    ]);
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(
        height: 32,
        width: 1,
        decoration: BoxDecoration(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
            borderRadius: BorderRadius.circular(Brand.r(1))));
  }

  // ─── CONTENT TYPE FILTER ───────────────────────────────────

  Widget _buildContentTypeFilter(bool isDark) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _contentTypes.length,
        itemBuilder: (context, index) {
          final cat = _contentTypes[index];
          final isSelected = _selectedContentType == cat['value'];
          final color = cat['value'] == 'all'
              ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
              : _getColorForType(cat['value'] as String);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedContentType = cat['value'] as String);
              _onFilterChanged();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color
                    : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: Border.all(
                    color: isSelected
                        ? color
                        : (isDark ? Brand.darkBorder : Brand.borderLight)),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: color.withAlpha(((0.35) * 255).toInt()),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              child: Row(children: [
                Icon(cat['icon'] as IconData,
                    size: 16, color: isSelected ? Colors.white : color),
                const SizedBox(width: 6),
                Text(cat['label'] as String,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight))),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ─── MACHINE CATEGORY FILTER ───────────────────────────────

  Widget _buildMachineCategoryFilter(bool isDark) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _machineCategories.length,
        itemBuilder: (context, index) {
          final cat = _machineCategories[index];
          final isSelected = _selectedMachineCategory == cat['value'];
          final isUserOwned = _userMachineCategories.contains(cat['value']);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedMachineCategory = cat['value'] as String);
              _onFilterChanged();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                        : Brand.royalBlueSurface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                  color: isSelected
                      ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                      : (isDark ? Brand.darkBorderLight : Brand.borderLight)
                          .withAlpha(((0.7) * 255).toInt()),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                Icon(cat['icon'] as IconData,
                    size: 14,
                    color: isSelected
                        ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                        : (isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight)),
                const SizedBox(width: 5),
                Text(cat['label'] as String,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected
                            ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight))),
                if (isUserOwned && cat['value'] != 'all') ...[
                  const SizedBox(width: 5),
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: Brand.lightGreenBright,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Brand.lightGreen.withAlpha(((0.4) * 255).toInt()),
                                blurRadius: 4)
                          ])),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isSearchExpanded ? 70 : 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isSearchExpanded ? 1.0 : 0.0,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(16)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                            color: Brand.royalBlue.withAlpha(13),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    fontWeight: FontWeight.w600),
                cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                autofocus: _isSearchExpanded,
                decoration: InputDecoration(
                  hintText: 'Search articles, guides, FAQs...',
                  hintStyle: TextStyle(
                      fontSize: 14,
                      color:
                          (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                              .withAlpha(153),
                      fontWeight: FontWeight.w500),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                      size: 22),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _applyLocalFilters());
                          })
                      : null,
                  filled: true,
                  fillColor: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      borderSide: BorderSide(
                          color:
                              isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          width: 1.5)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── RESULT HEADER ─────────────────────────────────────────

  Widget _buildResultHeader(bool isDark) {
    final hasActiveFilters = _selectedContentType != 'all' ||
        _selectedMachineCategory != 'all' ||
        _searchController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Brand.royalBlue, Brand.royalBlueGlow],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(Brand.r(2)))),
        const SizedBox(width: 10),
        Text(
            '${_filteredArticles.length} ${_filteredArticles.length == 1 ? 'Article' : 'Articles'}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                fontSize: 16,
                letterSpacing: -0.3)),
        const Spacer(),
        if (hasActiveFilters)
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedContentType = 'all';
                _selectedMachineCategory = 'all';
                _searchController.clear();
              });
              _onFilterChanged();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.red.withAlpha(((isDark ? 0.12 : 0.06) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(8)),
                  border: Border.all(color: Colors.red.withAlpha(((0.15) * 255).toInt()))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.clear_rounded, size: 14, color: Colors.red.shade400),
                const SizedBox(width: 4),
                Text('Clear',
                    style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        const SizedBox(width: 8),
        _buildSortButton(isDark),
      ]),
    );
  }

  Widget _buildSortButton(bool isDark) {
    return GestureDetector(
      onTap: () => _showSortOptions(isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(10)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort_rounded,
              size: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          const SizedBox(width: 5),
          Text(
              _sortBy == 'newest'
                  ? 'Newest'
                  : _sortBy == 'popular'
                      ? 'Popular'
                      : 'Oldest',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  void _showSortOptions(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Brand.r(24)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                  borderRadius: BorderRadius.circular(Brand.r(2)))),
          const SizedBox(height: 22),
          Text('Sort By',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.4)),
          const SizedBox(height: 18),
          _buildSortOption(
              'newest', 'Newest First', Icons.schedule_rounded, isDark),
          _buildSortOption(
              'popular', 'Most Popular', Icons.trending_up_rounded, isDark),
          _buildSortOption(
              'oldest', 'Oldest First', Icons.history_rounded, isDark),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildSortOption(
      String value, String label, IconData icon, bool isDark) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                      : Brand.royalBlueSurface)
                  : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
              borderRadius: BorderRadius.circular(Brand.r(14))),
          child: Icon(icon,
              color: isSelected
                  ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                  : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              size: 20)),
      title: Text(label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                  : (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark))),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue, size: 22)
          : null,
      onTap: () {
        Navigator.pop(context);
        setState(() => _sortBy = value);
        _onFilterChanged();
      },
    );
  }

  // ─── ARTICLES LIST ─────────────────────────────────────────

  Widget _buildArticlesList(bool isDark) {
    final showFeatured = _selectedContentType == 'all' &&
        _selectedMachineCategory == 'all' &&
        _searchController.text.isEmpty &&
        _filteredArticles.length > 3;

    Map<String, dynamic>? featured;
    if (showFeatured) {
      final sorted = List<Map<String, dynamic>>.from(_filteredArticles)
        ..sort((a, b) =>
            ((b['views'] ?? 0) as int).compareTo((a['views'] ?? 0) as int));
      featured = sorted.isNotEmpty ? sorted.first : null;
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: Brand.royalBlue,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        children: [
          if (_userMachineCategories.isNotEmpty &&
              _selectedContentType == 'all' &&
              _selectedMachineCategory == 'all' &&
              _searchController.text.isEmpty)
            _buildForYourMachinesSection(isDark),
          if (_recentlyViewed.isNotEmpty &&
              _selectedContentType == 'all' &&
              _searchController.text.isEmpty)
            _buildRecentlyViewedSection(isDark),
          if (featured != null && showFeatured) ...[
            _buildFeaturedCard(featured, isDark),
            const SizedBox(height: 22),
            Row(children: [
              Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Brand.royalBlue, Brand.royalBlueGlow]),
                      borderRadius: BorderRadius.circular(Brand.r(2)))),
              const SizedBox(width: 10),
              Text('All Articles',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      letterSpacing: -0.3)),
            ]),
            const SizedBox(height: 14),
          ],
          ..._filteredArticles
              .where((a) => featured == null || a['id'] != featured['id'])
              .map((article) => _buildArticleCard(article, isDark)),
          if (_isLoadingMore)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color:
                                isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                            strokeWidth: 2.5)))),
          if (!_hasMore && _filteredArticles.length >= _pageSize)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: Text("You've reached the end",
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontWeight: FontWeight.w500)))),
        ],
      ),
    );
  }

  // ─── FOR YOUR MACHINES SECTION ─────────────────────────────

  Widget _buildForYourMachinesSection(bool isDark) {
    final relevantArticles = _articles
        .where((a) =>
            a['machine_category'] != null &&
            _userMachineCategories.contains(a['machine_category']))
        .take(5)
        .toList();

    if (relevantArticles.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: isDark
                    ? Brand.lightGreen.withAlpha(((0.12) * 255).toInt())
                    : Brand.lightGreenSurface,
                borderRadius: BorderRadius.circular(Brand.r(10))),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 16, color: Brand.lightGreenBright)),
        const SizedBox(width: 10),
        Text('For Your Machines',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                letterSpacing: -0.3)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
          height: 135,
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: relevantArticles.length,
              itemBuilder: (_, i) =>
                  _buildCompactArticleCard(relevantArticles[i], isDark))),
      const SizedBox(height: 22),
    ]);
  }

  Widget _buildCompactArticleCard(Map<String, dynamic> article, bool isDark) {
    final contentType = article['content_type'] ?? 'guide';
    final color = _getColorForType(contentType);

    return GestureDetector(
      onTap: () => _openArticle(article),
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(18)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border: Border.all(color: color.withAlpha(((0.15) * 255).toInt()))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_getIconForType(contentType), size: 11, color: color),
                  const SizedBox(width: 4),
                  Text(_getTypeLabel(contentType),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.3)),
                ])),
            const Spacer(),
            if (article['machine_category'] != null)
              Text(article['machine_category'],
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500)),
          ]),
          const Spacer(),
          Text(article['title'] ?? '',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.visibility_rounded,
                size: 12,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            const SizedBox(width: 4),
            Text('${article['views'] ?? 0}',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  // ─── RECENTLY VIEWED ───────────────────────────────────────

  Widget _buildRecentlyViewedSection(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: isDark
                    ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                    : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(Brand.r(10))),
            child: Icon(Icons.history_rounded,
                size: 16,
                color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
        const SizedBox(width: 10),
        Text('Recently Viewed',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                letterSpacing: -0.3)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
          height: 52,
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentlyViewed.length,
              itemBuilder: (_, i) {
                final article = _recentlyViewed[i];
                final color = _getColorForType(article['content_type']);
                return GestureDetector(
                    onTap: () => _openArticle(article),
                    child: Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: Brand.surface(isDark),
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            border: Border.all(
                                color: isDark
                                    ? Brand.darkBorder
                                    : Brand.borderLight)),
                        child: Row(children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color:
                                      color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(Brand.r(10))),
                              child: Icon(
                                  _getIconForType(article['content_type']),
                                  size: 14,
                                  color: color)),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(article['title'] ?? '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Brand.darkTextPrimary
                                          : Brand.royalBlueDark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                        ])));
              })),
      const SizedBox(height: 22),
    ]);
  }

  // ─── FEATURED CARD ─────────────────────────────────────────

  Widget _buildFeaturedCard(Map<String, dynamic> article, bool isDark) {
    final contentType = article['content_type'] ?? 'guide';
    final isBookmarked = _bookmarkedIds.contains(article['id']?.toString());

    return GestureDetector(
      onTap: () => _openArticle(article),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkCard, Brand.darkCardElevated]
                    : [Brand.royalBlueDark, Brand.royalBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(Brand.r(24)),
            boxShadow: isDark ? null : [
              BoxShadow(
                  color: Brand.royalBlue.withAlpha(89),
                  blurRadius: 24,
                  offset: const Offset(0, 10))
            ]),
        child: Stack(children: [
          Positioned(
              right: -30,
              top: -30,
              child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(((0.04) * 255).toInt())))),
          Positioned(
              left: -15,
              bottom: -15,
              child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(((0.03) * 255).toInt())))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Brand.lightGreen.withAlpha(((0.18) * 255).toInt()),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                      border: Border.all(
                          color: Brand.lightGreen.withAlpha(((0.25) * 255).toInt()))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded,
                        color: Brand.lightGreenBright, size: 14),
                    SizedBox(width: 4),
                    Text('Most Popular',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Brand.lightGreenBright,
                            letterSpacing: 0.3)),
                  ])),
              const Spacer(),
              GestureDetector(
                  onTap: () => _toggleBookmark(article['id'].toString()),
                  child: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: isBookmarked
                          ? Colors.amber
                          : Colors.white.withAlpha(((0.4) * 255).toInt()),
                      size: 22)),
              const SizedBox(width: 10),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withAlpha(((0.08) * 255).toInt()),
                      borderRadius: BorderRadius.circular(Brand.r(8))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_getIconForType(contentType),
                        color: Colors.white.withAlpha(((0.5) * 255).toInt()), size: 13),
                    const SizedBox(width: 4),
                    Text(_getTypeLabel(contentType),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withAlpha(((0.5) * 255).toInt()),
                            fontWeight: FontWeight.w600)),
                  ])),
            ]),
            const SizedBox(height: 18),
            Text(article['title'] ?? 'Untitled',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                    letterSpacing: -0.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(article['content'] ?? '',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(((0.45) * 255).toInt()),
                    height: 1.4,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (article['tags'] != null &&
                (article['tags'] as List).isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: (article['tags'] as List).take(4).map((tag) {
                    return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.white.withAlpha(((0.06) * 255).toInt()),
                            borderRadius: BorderRadius.circular(Brand.r(10))),
                        child: Text('#$tag',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withAlpha(((0.35) * 255).toInt()),
                                fontWeight: FontWeight.w600)));
                  }).toList()),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.visibility_rounded,
                  size: 14, color: Colors.white.withAlpha(((0.3) * 255).toInt())),
              const SizedBox(width: 4),
              Text('${article['views'] ?? 0} views',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(((0.3) * 255).toInt()),
                      fontWeight: FontWeight.w500)),
              if (article['machine_category'] != null) ...[
                const SizedBox(width: 14),
                Icon(Icons.precision_manufacturing_rounded,
                    size: 14, color: Colors.white.withAlpha(((0.3) * 255).toInt())),
                const SizedBox(width: 4),
                Text(article['machine_category'],
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withAlpha(((0.3) * 255).toInt()),
                        fontWeight: FontWeight.w500)),
              ],
              const Spacer(),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: Brand.lightGreen.withAlpha(((0.18) * 255).toInt()),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                      border: Border.all(
                          color: Brand.lightGreen.withAlpha(((0.25) * 255).toInt()))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Read',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Brand.lightGreenBright)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 14, color: Brand.lightGreenBright),
                  ])),
            ]),
          ]),
        ]),
      ),
    );
  }

  // ─── ARTICLE CARD ──────────────────────────────────────────

  Widget _buildArticleCard(Map<String, dynamic> article, bool isDark) {
    final contentType = article['content_type'] ?? 'guide';
    final icon = _getIconForType(contentType);
    final color = _getColorForType(contentType);
    final readTime = article['estimated_read_time'] ?? 3;
    // FIX #9: Use TimeUtils instead of local _getTimeAgo
    final timeAgo = article['created_at'] != null
        ? TimeUtils.getTimeAgo(
            DateTime.tryParse(article['created_at'].toString()) ??
                DateTime.now())
        : '';
    final isBookmarked = _bookmarkedIds.contains(article['id']?.toString());
    final tags = article['tags'] as List?;

    return GestureDetector(
      onTap: () => _openArticle(article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(10),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
        child: Row(children: [
          Container(
              width: 4,
              height: 105,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(Brand.r(20)),
                      bottomLeft: Radius.circular(Brand.r(20))))),
          Container(
              width: 60,
              height: 105,
              margin: const EdgeInsets.only(left: 12),
              child: Center(
                  child: article['thumbnail_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          child: CachedNetworkImage(
                              imageUrl: article['thumbnail_url'],
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _buildTypeIcon(icon, color, isDark)))
                      : _buildTypeIcon(icon, color, isDark))),
          Expanded(
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color:
                                      color.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(Brand.r(10)),
                                  border: Border.all(
                                      color: color.withAlpha(((0.15) * 255).toInt()))),
                              child: Text(
                                  _getTypeLabel(contentType).toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                      letterSpacing: 0.5))),
                          if (article['machine_category'] != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(article['machine_category'],
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Brand.darkTextSecondary
                                            : Brand.subtleLight,
                                        fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis)),
                          ],
                          const Spacer(),
                          if (timeAgo.isNotEmpty)
                            Text(timeAgo,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight.withAlpha(((0.6) * 255).toInt()),
                                    fontWeight: FontWeight.w500)),
                        ]),
                        const SizedBox(height: 8),
                        Text(article['title'] ?? 'Untitled',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                                height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.schedule_rounded,
                              size: 12,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight.withAlpha(((0.6) * 255).toInt())),
                          const SizedBox(width: 4),
                          Text('$readTime min',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 10),
                          Icon(Icons.visibility_rounded,
                              size: 12,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight.withAlpha(((0.6) * 255).toInt())),
                          const SizedBox(width: 4),
                          Text('${article['views'] ?? 0}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                  fontWeight: FontWeight.w500)),
                          if (tags != null && tags.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.tag_rounded,
                                size: 12,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight.withAlpha(((0.6) * 255).toInt())),
                            const SizedBox(width: 4),
                            Text('${tags.length}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ]),
                      ]))),
          Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(children: [
                GestureDetector(
                    onTap: () => _toggleBookmark(article['id'].toString()),
                    child: Icon(
                        isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                        color: isBookmarked
                            ? Colors.amber
                            : (isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight.withAlpha(((0.3) * 255).toInt())))),
                const SizedBox(height: 18),
                Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withAlpha(((0.04) * 255).toInt())
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(10))),
                    child: Icon(Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.royalBlue.withAlpha(((0.35) * 255).toInt()))),
              ])),
        ]),
      ),
    );
  }

  Widget _buildTypeIcon(IconData icon, Color color, bool isDark) {
    return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            color: color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
            borderRadius: BorderRadius.circular(Brand.r(14))),
        child: Icon(icon, color: color, size: 24));
  }

  // ─── BOOKMARKED ARTICLES SHEET ─────────────────────────────

  void _showBookmarkedArticles(bool isDark) {
    if (_bookmarkedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.bookmark_border_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('No saved articles yet',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: Brand.royalBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
          margin: const EdgeInsets.all(16)));
      return;
    }

    final bookmarked = _articles
        .where((a) => _bookmarkedIds.contains(a['id']?.toString()))
        .toList();

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            builder: (_, sc) => Container(
                decoration: BoxDecoration(
                    color: Brand.surface(isDark),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(Brand.r(24)))),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: isDark
                                    ? Brand.darkBorderLight
                                    : Brand.borderLight,
                                borderRadius: BorderRadius.circular(Brand.r(2)))),
                        const SizedBox(height: 18),
                        Row(children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: Colors.amber
                                      .withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(Brand.r(11))),
                              child: const Icon(Icons.bookmark_rounded,
                                  color: Colors.amber, size: 18)),
                          const SizedBox(width: 12),
                          Text('Saved Articles (${bookmarked.length})',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.royalBlueDark,
                                  letterSpacing: -0.4)),
                        ]),
                      ])),
                  Expanded(
                      child: bookmarked.isEmpty
                          ? Center(
                              child: Text('No saved articles',
                                  style: TextStyle(
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight,
                                      fontWeight: FontWeight.w500)))
                          : ListView.builder(
                              controller: sc,
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              itemCount: bookmarked.length,
                              itemBuilder: (_, i) =>
                                  _buildArticleCard(bookmarked[i], isDark))),
                ]))));
  }

  // ─── EMPTY STATE ───────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    final isFiltered = _selectedContentType != 'all' ||
        _selectedMachineCategory != 'all' ||
        _searchController.text.isNotEmpty;

    return Center(
        child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(40),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                      color: isDark
                          ? Brand.royalBlue.withAlpha(((0.1) * 255).toInt())
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(26))),
                  child: Icon(
                      isFiltered
                          ? Icons.search_off_rounded
                          : Icons.menu_book_rounded,
                      size: 42,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
              const SizedBox(height: 22),
              Text(isFiltered ? 'No Articles Found' : 'No Articles Yet',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      letterSpacing: -0.4)),
              const SizedBox(height: 10),
              Text(
                  isFiltered
                      ? 'Try adjusting your search or filters'
                      : 'Knowledge base articles will appear here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      height: 1.5,
                      fontWeight: FontWeight.w500)),
              if (isFiltered) ...[
                const SizedBox(height: 24),
                GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedContentType = 'all';
                        _selectedMachineCategory = 'all';
                        _searchController.clear();
                      });
                      _onFilterChanged();
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Brand.royalBlueDark, Brand.royalBlue]),
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            boxShadow: [
                              BoxShadow(
                                  color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5))
                            ]),
                        child: const Text('Clear Filters',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 14)))),
              ],
            ])));
  }

  // ─── SKELETON LOADING ──────────────────────────────────────

  Widget _buildSkeletonLoading(bool isDark) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildSkeletonFeatured(isDark),
          const SizedBox(height: 16),
          ...List.generate(4, (_) => _buildSkeletonCard(isDark)),
        ]);
  }

  Widget _buildSkeletonFeatured(bool isDark) {
    return Container(
        height: 200,
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(24)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null),
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _skBox(80, 24, isDark),
            const Spacer(),
            _skBox(60, 24, isDark),
          ]),
          const SizedBox(height: 22),
          _skBox(double.infinity, 20, isDark),
          const SizedBox(height: 10),
          _skBox(200, 16, isDark),
          const Spacer(),
          Row(children: [
            _skBox(60, 14, isDark),
            const SizedBox(width: 16),
            _skBox(60, 14, isDark),
            const Spacer(),
            _skBox(70, 30, isDark),
          ]),
        ]));
  }

  Widget _buildSkeletonCard(bool isDark) {
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null),
        child: Row(children: [
          _skBox(48, 48, isDark, radius: 14),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  _skBox(50, 18, isDark),
                  const SizedBox(width: 8),
                  _skBox(40, 14, isDark),
                ]),
                const SizedBox(height: 10),
                _skBox(double.infinity, 16, isDark),
                const SizedBox(height: 6),
                _skBox(140, 14, isDark),
                const SizedBox(height: 10),
                _skBox(100, 12, isDark),
              ])),
        ]));
  }

  Widget _skBox(double w, double h, bool isDark, {double radius = 8}) {
    return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withAlpha(((0.04) * 255).toInt())
                : Brand.royalBlue.withAlpha(((0.05) * 255).toInt()),
            borderRadius: BorderRadius.circular(radius)));
  }
}
