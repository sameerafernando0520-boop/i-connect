// lib/screens/marketing/ma_knowledge_base_page.dart
// P5 — Knowledge Base: full CRUD for articles

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _kbColor = Color(0xFF8B5CF6);

class MaKnowledgeBasePage extends StatefulWidget {
  const MaKnowledgeBasePage({super.key});

  @override
  State<MaKnowledgeBasePage> createState() => _MaKnowledgeBasePageState();
}

class _MaKnowledgeBasePageState extends State<MaKnowledgeBasePage> {
  List<Map<String, dynamic>> _articles = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all', 'published', 'draft'
  final _searchCtrl = TextEditingController();
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client
          .from('knowledge_base')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _articles = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _articles;
    if (_filter == 'published') {
      list = list.where((a) => a['is_published'] == true).toList();
    } else if (_filter == 'draft') {
      list = list.where((a) => a['is_published'] != true).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((a) {
        final title = (a['title'] ?? '').toString().toLowerCase();
        final cat = (a['content_type'] ?? a['category'] ?? '').toString().toLowerCase();
        return title.contains(q) || cat.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ArticleFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseConfig.client.from('knowledge_base').insert({
        'title': result['title'],
        'content': result['content'],
        'content_type': result['content_type'],
        'machine_category': result['machine_category'],
        'tags': result['tags'],
        'is_published': result['is_published'],
      });
      if (!mounted) return;
      _showSuccess('Article created');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _edit(Map<String, dynamic> article) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ArticleFormDialog(initial: article),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseConfig.client.from('knowledge_base').update({
        'title': result['title'],
        'content': result['content'],
        'content_type': result['content_type'],
        'machine_category': result['machine_category'],
        'tags': result['tags'],
        'is_published': result['is_published'],
      }).eq('id', article['id']);
      if (!mounted) return;
      _showSuccess('Article updated');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Article'),
        content: Text('Delete "${article['title']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseConfig.client.from('knowledge_base').delete().eq('id', article['id']);
      if (!mounted) return;
      _showSuccess('Article deleted');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _togglePublish(Map<String, dynamic> article) async {
    final newVal = !(article['is_published'] as bool? ?? false);
    try {
      await SupabaseConfig.client.from('knowledge_base')
          .update({'is_published': newVal}).eq('id', article['id']);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: AdminColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Knowledge Base',
        accent: HeroAccent.violet,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // ── Search + Filter Bar ──
          Container(
            color: Brand.surface(isDark),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search articles…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                        : null,
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'All', isDark),
                      const SizedBox(width: 8),
                      _filterChip('published', 'Published', isDark),
                      const SizedBox(width: 8),
                      _filterChip('draft', 'Draft', isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Article List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kbColor))
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: AdminColors.error.withAlpha(20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.error_outline_rounded, size: 32, color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          Text('Something went wrong',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                            style: FilledButton.styleFrom(backgroundColor: _kbColor),
                          ),
                        ]),
                      ))
                    : RefreshIndicator(
                        onRefresh: _load, color: _kbColor,
                        child: filtered.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 80),
                                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    width: 72, height: 72,
                                    decoration: BoxDecoration(
                                      color: _kbColor.withAlpha(20),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.article_outlined, size: 36, color: _kbColor),
                                  ),
                                  const SizedBox(height: 20),
                                  Text('No articles found',
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                                  const SizedBox(height: 8),
                                  Text(_search.isNotEmpty ? 'Try a different search term.' : 'Tap + to create your first article.',
                                      style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                                ])),
                              ])
                            : Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('${filtered.length} article${filtered.length == 1 ? '' : 's'}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                              color: AdminColors.textHint(context))),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (_, i) => _buildCard(filtered[i], isDark),
                                    ),
                                  ),
                                ],
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Article', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kbColor, foregroundColor: Colors.white,
      ),
    );
  }

  Widget _filterChip(String value, String label, bool isDark) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _kbColor : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(color: isSelected ? _kbColor : (isDark ? Brand.darkBorder : Brand.borderLight)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AdminColors.textHint(context))),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> a, bool isDark) {
    final isPublished = a['is_published'] as bool? ?? false;
    final type = a['content_type'] as String? ?? a['category'] as String? ?? '—';
    final views = a['views_count'] as int? ?? a['views'] as int? ?? 0;
    final createdAt = a['created_at'] as String?;

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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(a['title'] ?? 'Untitled',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isPublished ? AdminColors.success : AdminColors.warning).withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(isPublished ? 'Published' : 'Draft',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: isPublished ? AdminColors.success : AdminColors.warning)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            _meta(Icons.category_outlined, type, isDark),
            const SizedBox(width: 12),
            _meta(Icons.visibility_outlined, '$views views', isDark),
            if (createdAt != null) ...[
              const SizedBox(width: 12),
              _meta(Icons.schedule_outlined,
                  TimeUtils.formatDateShort(DateTime.tryParse(createdAt) ?? DateTime.now()), isDark),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _actionBtn(Icons.edit_rounded, 'Edit', _kbColor, isDark, () => _edit(a)),
            const SizedBox(width: 8),
            _actionBtn(
              isPublished ? Icons.unpublished_outlined : Icons.publish_rounded,
              isPublished ? 'Unpublish' : 'Publish',
              isPublished ? AdminColors.warning : AdminColors.success,
              isDark, () => _togglePublish(a),
            ),
            const SizedBox(width: 8),
            _actionBtn(Icons.delete_outline_rounded, 'Delete', AdminColors.error, isDark, () => _delete(a)),
          ]),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text, bool isDark) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AdminColors.textHint(context)),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
    ]);
  }

  Widget _actionBtn(IconData icon, String label, Color color, bool isDark, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(Brand.r(10)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 25 : 12),
            borderRadius: BorderRadius.circular(Brand.r(10)),
            border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
          ),
          child: Column(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }
}

// ─── Article Form Dialog ───────────────────────────────────────────────────────

class _ArticleFormDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _ArticleFormDialog({this.initial});

  @override
  State<_ArticleFormDialog> createState() => _ArticleFormDialogState();
}

class _ArticleFormDialogState extends State<_ArticleFormDialog> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _contentType = 'manual';
  String _machineCategory = 'general';
  bool _isPublished = false;

  static const _contentTypes = ['manual', 'troubleshooting', 'video', 'faq', 'guide'];
  static const _categories = ['general', 'compressors', 'generators', 'pumps', 'motors', 'other'];

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _titleCtrl.text = a['title'] ?? '';
      _contentCtrl.text = a['content'] ?? '';
      _contentType = a['content_type'] as String? ?? 'manual';
      _machineCategory = a['machine_category'] as String? ?? 'general';
      _isPublished = a['is_published'] as bool? ?? false;
      final tags = a['tags'];
      if (tags is List) {
        _tagsCtrl.text = tags.join(', ');
      } else if (tags is String) {
        _tagsCtrl.text = tags;
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tagsCtrl.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New Article' : 'Edit Article'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                  labelText: 'Title *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'Content', border: OutlineInputBorder(),
                  alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _contentType,
              decoration: const InputDecoration(
                  labelText: 'Content Type', border: OutlineInputBorder()),
              items: _contentTypes.map((t) => DropdownMenuItem(
                  value: t, child: Text(_cap(t)))).toList(),
              onChanged: (v) => setState(() => _contentType = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _machineCategory,
              decoration: const InputDecoration(
                  labelText: 'Machine Category', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(
                  value: c, child: Text(_cap(c)))).toList(),
              onChanged: (v) => setState(() => _machineCategory = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  border: OutlineInputBorder(),
                  hintText: 'maintenance, safety, oil'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Published'),
              subtitle: const Text('Visible to customers'),
              value: _isPublished,
              onChanged: (v) => setState(() => _isPublished = v),
              activeThumbColor: _kbColor,
              contentPadding: EdgeInsets.zero,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'title': _titleCtrl.text.trim(),
              'content': _contentCtrl.text.trim(),
              'content_type': _contentType,
              'machine_category': _machineCategory,
              'tags': _parsedTags,
              'is_published': _isPublished,
            });
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: _kbColor, foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
