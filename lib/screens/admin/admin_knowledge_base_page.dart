// lib/screens/admin/admin_knowledge_base_page.dart
//
// Admin-side Knowledge Base manager (v22).
// Lists all knowledge_base rows with type filter chips, search, and inline
// publish-toggle. Tap to edit, long-press for delete.
// FAB opens AdminKnowledgeBaseFormPage in create mode.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import 'admin_knowledge_base_form_page.dart';

class AdminKnowledgeBasePage extends StatefulWidget {
  const AdminKnowledgeBasePage({super.key});

  @override
  State<AdminKnowledgeBasePage> createState() => _AdminKnowledgeBasePageState();
}

class _AdminKnowledgeBasePageState extends State<AdminKnowledgeBasePage> {
  // ─── Type catalogue ──────────────────────────────────────────
  // Keep these labels and values aligned with the form page and the
  // CHECK constraint applied in the v22 schema migration.
  static const _types = <_KbType>[
    _KbType('all',         'All',          Icons.dashboard_rounded,           Color(0xFF6366F1)),
    _KbType('manual',      'Manuals',      Icons.menu_book_rounded,           Color(0xFF3B82F6)),
    _KbType('article',     'Articles',     Icons.article_rounded,             Color(0xFF8B5CF6)),
    _KbType('testimonial', 'Testimonials', Icons.format_quote_rounded,        Color(0xFFEC4899)),
    _KbType('video',       'Videos',       Icons.play_circle_fill_rounded,    Color(0xFFEF4444)),
  ];

  // ─── State ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;
  String _typeFilter = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();

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

  // ─── Data ────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await SupabaseConfig.client
          .from('knowledge_base')
          .select(
            'id, title, content, content_type, category, '
            'machine_id, machine_model, machine_category, '
            'video_url, pdf_url, thumbnail_url, '
            'customer_name, customer_role, '
            'is_published, views, helpful_count, display_order, '
            'created_at, '
            'machine:machine_catalog!machine_id(id, machine_name, image_url)',
          )
          .order('display_order', ascending: true)
          .order('created_at', ascending: false);

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

  Future<void> _togglePublished(Map<String, dynamic> item) async {
    final newVal = !(item['is_published'] as bool? ?? false);
    // Optimistic update
    setState(() => item['is_published'] = newVal);
    try {
      await SupabaseConfig.client
          .from('knowledge_base')
          .update({'is_published': newVal})
          .eq('id', item['id']);
    } catch (e) {
      // Revert + notify
      if (!mounted) return;
      setState(() => item['is_published'] = !newVal);
      _showError('Could not update publish state: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'This will permanently remove "${item['title']}" from the customer Knowledge Base.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseConfig.client
          .from('knowledge_base')
          .delete()
          .eq('id', item['id']);
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e['id'] == item['id']));
      _showSnack('Entry deleted', AdminColors.success);
    } catch (e) {
      if (!mounted) return;
      _showError('Delete failed: $e');
    }
  }

  // ─── UI helpers ──────────────────────────────────────────────
  void _showError(String msg) => _showSnack(msg, AdminColors.error);

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      ),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _items.where((m) {
      if (_typeFilter != 'all' && m['content_type'] != _typeFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        m['title'],
        m['content'],
        m['category'],
        m['machine_model'],
        m['customer_name'],
        m['customer_role'],
      ].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  _KbType _typeFor(String? key) =>
      _types.firstWhere((t) => t.key == (key ?? ''), orElse: () => _types.first);

  // ─── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Knowledge Base',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _isLoading ? null : _load,
            tooltip: 'Reload',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminKnowledgeBaseFormPage(),
            ),
          );
          if (created == true) _load();
        },
        backgroundColor: Brand.royalBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Entry',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildSearch(isDark),
          _buildTypeFilters(isDark),
          Expanded(child: _buildList(isDark)),
        ],
      ),
    );
  }

  Widget _buildSearch(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search title, machine, or content',
          prefixIcon: Icon(Icons.search_rounded,
              color: AdminColors.textHint(context)),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                ),
          filled: true,
          fillColor: Brand.surface(isDark),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide:
                BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide:
                BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide(color: Brand.royalBlue, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTypeFilters(bool isDark) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = _types[i];
          final sel = _typeFilter == t.key;
          final count = t.key == 'all'
              ? _items.length
              : _items.where((m) => m['content_type'] == t.key).length;
          return GestureDetector(
            onTap: () => setState(() => _typeFilter = t.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? t.color.withAlpha(isDark ? 50 : 30)
                    : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: Border.all(
                  color: sel
                      ? t.color
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: sel ? 1.4 : 1,
                ),
              ),
              child: Row(children: [
                Icon(t.icon, size: 16, color: sel ? t.color : AdminColors.textHint(context)),
                const SizedBox(width: 6),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? t.color : AdminColors.text(context),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sel ? t.color : AdminColors.textHint(context).withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ]),
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
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: AdminColors.textHint(context)),
              const SizedBox(height: 12),
              Text(
                _search.isNotEmpty
                    ? 'No entries match your search'
                    : 'No entries in this category yet',
                style: TextStyle(color: AdminColors.textSub(context)),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap the + button to add a manual, article, testimonial, or video.',
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(list[i], isDark),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> m, bool isDark) {
    final t = _typeFor(m['content_type'] as String?);
    final published = m['is_published'] as bool? ?? false;
    final views = (m['views'] as num?)?.toInt() ??
        (m['views_count'] as num?)?.toInt() ??
        0;
    final helpful = (m['helpful_count'] as num?)?.toInt() ?? 0;
    final machineMap = m['machine'] as Map<String, dynamic>?;
    final machineName = machineMap?['machine_name'] as String? ??
        m['machine_model'] as String? ??
        '';
    final thumbnail = (m['thumbnail_url'] as String?) ??
        (machineMap?['image_url'] as String?);

    return InkWell(
      onTap: () async {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => AdminKnowledgeBaseFormPage(existing: m),
          ),
        );
        if (saved == true) _load();
      },
      onLongPress: () => _delete(m),
      borderRadius: BorderRadius.circular(Brand.r(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail / type icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: t.color.withAlpha(isDark ? 60 : 25),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumbnail != null && thumbnail.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbnail,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Center(child: Icon(t.icon, color: t.color)),
                        errorWidget: (_, __, ___) =>
                            Center(child: Icon(t.icon, color: t.color)),
                      )
                    : Icon(t.icon, color: t.color, size: 28),
              ),
              const SizedBox(width: 12),
              // Title + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.color.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          t.label.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: t.color),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (!published)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.warning.withAlpha(35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'DRAFT',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AdminColors.warning),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      m['title']?.toString() ?? 'Untitled',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(context),
                      ),
                    ),
                    if (machineName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.precision_manufacturing_rounded,
                            size: 13,
                            color: AdminColors.textSub(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            machineName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSub(context)),
                          ),
                        ),
                      ]),
                    ],
                    if (m['content_type'] == 'testimonial' &&
                        (m['customer_name'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        '“${m['customer_name']}”'
                        '${(m['customer_role'] as String?)?.isNotEmpty == true ? ' · ${m['customer_role']}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AdminColors.textSub(context)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.visibility_rounded,
                          size: 12, color: AdminColors.textHint(context)),
                      const SizedBox(width: 3),
                      Text('$views',
                          style: TextStyle(
                              fontSize: 11,
                              color: AdminColors.textHint(context))),
                      const SizedBox(width: 12),
                      Icon(Icons.thumb_up_rounded,
                          size: 12, color: AdminColors.textHint(context)),
                      const SizedBox(width: 3),
                      Text('$helpful',
                          style: TextStyle(
                              fontSize: 11,
                              color: AdminColors.textHint(context))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Publish toggle
              Column(
                children: [
                  Switch(
                    value: published,
                    onChanged: (_) => _togglePublished(m),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeThumbColor: AdminColors.success,
                  ),
                  Text(
                    published ? 'Live' : 'Draft',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: published
                            ? AdminColors.success
                            : AdminColors.textHint(context)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KbType {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _KbType(this.key, this.label, this.icon, this.color);
}
