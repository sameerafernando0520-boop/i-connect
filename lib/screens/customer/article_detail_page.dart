// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/customer/article_detail_page.dart
// REWRITTEN v18 — Full feature article detail with bookmarks,
//   share, related articles, view tracking, dark mode,
//   .withAlpha() throughout, correct DB column names
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../utils/time_utils.dart';

class ArticleDetailPage extends StatefulWidget {
  final dynamic articleId;
  const ArticleDetailPage({super.key, required this.articleId});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  Map<String, dynamic>? _article;
  List<Map<String, dynamic>> _relatedArticles = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isBookmarked = false;
  bool _bookmarkLoading = false;

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  // ═══════════════════════════════════════════════════════════
  // DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadArticle() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;

      final articleFuture = SupabaseConfig.client
          .from('knowledge_base')
          .select('*')
          .eq('id', widget.articleId)
          .maybeSingle();

      final bookmarkFuture = userId != null
          ? SupabaseConfig.client
              .from('user_bookmarks')
              .select('id')
              .eq('user_id', userId)
              .eq('article_id', widget.articleId)
              .maybeSingle()
          : Future<Map<String, dynamic>?>.value(null);

      final results = await Future.wait<dynamic>([
        articleFuture,
        bookmarkFuture,
      ]);
      if (!mounted) return;

      final article = results[0] as Map<String, dynamic>?;
      final bookmark = results[1] as Map<String, dynamic>?;

      setState(() {
        _article = article != null ? Map<String, dynamic>.from(article) : null;
        _isBookmarked = bookmark != null;
        _isLoading = false;
        _hasError = _article == null;
      });

      if (_article != null) {
        _trackView();
        _loadRelatedArticles();
      }
    } catch (e) {
      debugPrint('Article load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _trackView() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      // article_views is an event log (one row per view event), so just
      // insert a new row each time the article is opened.
      await SupabaseConfig.client.from('article_views').insert({
        'user_id': userId,
        'article_id': widget.articleId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Bump the aggregate counter atomically server-side. RLS no longer
      // allows customers to UPDATE knowledge_base rows directly.
      await SupabaseConfig.client.rpc(
        'increment_article_view_count',
        params: {'p_article_id': widget.articleId},
      );
    } catch (_) {}
  }

  Future<void> _loadRelatedArticles() async {
    try {
      final category = _article?['category'] as String?;

      var query = SupabaseConfig.client
          .from('knowledge_base')
          .select('id, title, category, tags, views_count, created_at')
          .eq('is_published', true)
          .neq('id', widget.articleId);

      if (category != null) {
        query = query.eq('category', category);
      }

      final data = await query.order('views_count', ascending: false).limit(5);

      if (!mounted) return;
      setState(() {
        _relatedArticles = List<Map<String, dynamic>>.from(data);
      });
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _bookmarkLoading = true);

    try {
      if (_isBookmarked) {
        await SupabaseConfig.client
            .from('user_bookmarks')
            .delete()
            .eq('user_id', userId)
            .eq('article_id', widget.articleId);
      } else {
        await SupabaseConfig.client.from('user_bookmarks').upsert(
          {
            'user_id': userId,
            'article_id': widget.articleId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,article_id',
        );
      }

      if (!mounted) return;
      setState(() {
        _isBookmarked = !_isBookmarked;
        _bookmarkLoading = false;
      });

      _showSnack(_isBookmarked ? 'Article bookmarked' : 'Bookmark removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _bookmarkLoading = false);
      _showSnack('Failed to update bookmark', isError: true);
    }
  }

  void _shareArticle() {
    if (_article == null) return;
    final title = _article!['title'] ?? 'Article';
    final content = _article!['content'] as String? ?? '';
    final preview =
        content.length > 200 ? '${content.substring(0, 200)}...' : content;
    SharePlus.instance.share(ShareParams(text: '$title\n\n$preview\n\n— iFrontiers Connect'));
  }

  void _copyContent() {
    if (_article == null) return;
    Clipboard.setData(ClipboardData(text: _article!['content'] ?? ''));
    _showSnack('Article content copied');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
      backgroundColor: isError ? Colors.red : Brand.lightGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'guides':
      case 'guide':
        return Icons.menu_book_rounded;
      case 'faq':
      case 'faqs':
        return Icons.help_outline_rounded;
      case 'troubleshooting':
        return Icons.build_rounded;
      case 'maintenance':
        return Icons.engineering_rounded;
      case 'safety':
        return Icons.health_and_safety_rounded;
      case 'announcements':
        return Icons.campaign_rounded;
      default:
        return Icons.article_rounded;
    }
  }

  int _estimateReadTime(String content) {
    final wordCount = content.split(RegExp(r'\s+')).length;
    final minutes = (wordCount / 200).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body: _isLoading
            ? _buildLoading(isDark)
            : _hasError
                ? _buildError(isDark)
                : RefreshIndicator(
                    onRefresh: _loadArticle,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    child: _buildContent(isDark),
                  ),
      ),
    );
  }

  // ─── LOADING ───────────────────────────────────────────────

  Widget _buildLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading article...',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }

  // ─── ERROR ─────────────────────────────────────────────────

  Widget _buildError(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(22),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(isDark ? 31 : 15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.article_outlined,
                    size: 38,
                    color:
                        isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400),
              ),
              const SizedBox(height: 20),
              Text(
                'Article Not Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This article may have been removed\nor is no longer available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: const Text('Go Back',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Brand.darkIconActive : Brand.royalBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CONTENT ───────────────────────────────────────────────

  Widget _buildContent(bool isDark) {
    final article = _article!;
    final title = article['title'] as String? ?? '';
    final content = article['content'] as String? ?? '';
    final category = article['category'] as String?;
    final viewCount = article['views_count'] as int? ?? 0;
    final readTime = _estimateReadTime(content);
    final tags = article['tags'] as List?;
    final createdAt = article['created_at'] as String?;


    return CustomScrollView(
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        // ── App Bar ──
        SliverAppBar(
          pinned: true,
          backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
          foregroundColor: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          elevation: 0,
          leading: _buildBackButton(isDark),
          actions: [
            _buildActionButton(
              icon: _bookmarkLoading
                  ? null
                  : (_isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded),
              color: _isBookmarked
                  ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                  : null,
              onTap: _toggleBookmark,
              isDark: isDark,
              isLoading: _bookmarkLoading,
              tooltip: _isBookmarked ? 'Remove bookmark' : 'Bookmark',
            ),
            _buildActionButton(
              icon: Icons.share_rounded,
              onTap: _shareArticle,
              isDark: isDark,
              tooltip: 'Share',
            ),
            _buildActionButton(
              icon: Icons.copy_rounded,
              onTap: _copyContent,
              isDark: isDark,
              tooltip: 'Copy',
            ),
            const SizedBox(width: 8),
          ],
        ),

        // ── Article Body ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category + icon header
                if (category != null) _buildCategoryHeader(category, isDark),

                const SizedBox(height: 16),

                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    height: 1.25,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 14),

                // Stats row
                _buildStatsRow(viewCount, readTime, createdAt, isDark),
                const SizedBox(height: 24),

                // Content body
                SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    height: 1.75,
                    letterSpacing: 0.1,
                  ),
                ),

                // Tags
                if (tags != null && tags.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _buildTagsSection(tags, isDark),
                ],

                // Bookmark CTA
                const SizedBox(height: 28),
                _buildBookmarkCTA(isDark),
              ],
            ),
          ),
        ),

        // ── Related Articles ──
        if (_relatedArticles.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildRelatedArticles(isDark),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _buildBackButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Brand.darkCardElevated.withAlpha(230)
              : Brand.cardLight.withAlpha(230),
          borderRadius: BorderRadius.circular(12),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    VoidCallback? onTap,
    Color? color,
    required bool isDark,
    bool isLoading = false,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkCardElevated.withAlpha(230)
                  : Brand.cardLight.withAlpha(230),
              borderRadius: BorderRadius.circular(12),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
            ),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    ),
                  )
                : Icon(
                    icon,
                    size: 18,
                    color: color ??
                        (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String category, bool isDark) {
    final color = isDark ? Brand.darkIconActive : Brand.royalBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 26 : 20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getCategoryIcon(category), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            category,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
      int viewCount, int readTime, String? createdAt, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Row(
        children: [
          _buildStatItem(
            Icons.visibility_rounded,
            '$viewCount views',
            isDark,
          ),
          _buildDividerDot(isDark),
          _buildStatItem(
            Icons.schedule_rounded,
            '$readTime min read',
            isDark,
          ),
          if (createdAt != null) ...[
            _buildDividerDot(isDark),
            _buildStatItem(
              Icons.access_time_rounded,
              TimeUtils.getTimeAgo(
                  DateTime.tryParse(createdAt) ?? DateTime.now()),
              isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, bool isDark) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerDot(bool isDark) {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkBorderLight : Brand.borderLight,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTagsSection(List tags, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag_rounded,
                size: 16,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            const SizedBox(width: 6),
            Text(
              'Tags',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight),
              ),
              child: Text(
                '#$tag',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBookmarkCTA(bool isDark) {
    final accentColor = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withAlpha(26),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_outlined,
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBookmarked ? 'Article Saved' : 'Save for Later',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isBookmarked
                      ? 'This article is in your bookmarks'
                      : 'Bookmark this article to read later',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _toggleBookmark,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _isBookmarked ? accentColor : accentColor.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isBookmarked ? 'Saved' : 'Save',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _isBookmarked ? Colors.white : accentColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedArticles(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue),
              const SizedBox(width: 8),
              Text(
                'Related Articles',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._relatedArticles.map((a) => _buildRelatedCard(a, isDark)),
        ],
      ),
    );
  }

  Widget _buildRelatedCard(Map<String, dynamic> article, bool isDark) {
    final title = article['title'] as String? ?? '';
    final viewCount = article['views_count'] as int? ?? 0;
    final category = article['category'] as String?;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArticleDetailPage(articleId: article['id']),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(16),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getCategoryIcon(category),
                size: 24,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.visibility_rounded,
                          size: 12,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight),
                      const SizedBox(width: 4),
                      Text(
                        '$viewCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight,
                        ),
                      ),
                      if (category != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.folder_rounded,
                            size: 12,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }
}
