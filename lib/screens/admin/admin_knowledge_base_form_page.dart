// lib/screens/admin/admin_knowledge_base_form_page.dart
//
// Admin Knowledge Base — create / edit form (v22).
// Supports four content types with type-specific fields:
//   - manual       → PDF link + summary
//   - article      → rich body text + author
//   - testimonial  → customer_name / customer_role / quote / photo
//   - video        → video URL + summary
// Common fields:  linked machine (machine_catalog), category, tags,
// thumbnail URL, display order, is_published.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

class AdminKnowledgeBaseFormPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const AdminKnowledgeBaseFormPage({super.key, this.existing});

  @override
  State<AdminKnowledgeBaseFormPage> createState() =>
      _AdminKnowledgeBaseFormPageState();
}

class _AdminKnowledgeBaseFormPageState
    extends State<AdminKnowledgeBaseFormPage> {
  // ─── Type catalogue ──────────────────────────────────────────
  static const _types = <_KbType>[
    _KbType('manual',      'Manual',       Icons.menu_book_rounded,        Color(0xFF3B82F6)),
    _KbType('article',     'Article',      Icons.article_rounded,          Color(0xFF8B5CF6)),
    _KbType('testimonial', 'Testimonial',  Icons.format_quote_rounded,     Color(0xFFEC4899)),
    _KbType('video',       'Video',        Icons.play_circle_fill_rounded, Color(0xFFEF4444)),
  ];

  final _formKey = GlobalKey<FormState>();

  // Common fields
  String _type = 'manual';
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _thumbnailCtrl = TextEditingController();
  final _displayOrderCtrl = TextEditingController(text: '0');
  bool _isPublished = true;

  // Type-specific
  final _pdfUrlCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _customerRoleCtrl = TextEditingController();

  // Linked machine
  String? _machineId;
  String? _machineName;
  List<Map<String, dynamic>> _machines = [];
  bool _machinesLoading = true;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _loadMachines();
    final e = widget.existing;
    if (e != null) {
      _type = (e['content_type'] as String?) ?? 'manual';
      // Coerce any legacy values into one of the four supported types so the
      // chip selector shows something. Anything else falls back to 'article'.
      if (!_types.any((t) => t.key == _type)) _type = 'article';
      _titleCtrl.text = e['title']?.toString() ?? '';
      _contentCtrl.text = e['content']?.toString() ?? '';
      _categoryCtrl.text = e['category']?.toString() ?? '';
      _authorCtrl.text = e['author']?.toString() ?? '';
      final tags = e['tags'];
      if (tags is List) _tagsCtrl.text = tags.join(', ');
      _thumbnailCtrl.text = e['thumbnail_url']?.toString() ?? '';
      _displayOrderCtrl.text = '${e['display_order'] ?? 0}';
      _isPublished = e['is_published'] as bool? ?? true;
      _pdfUrlCtrl.text = e['pdf_url']?.toString() ?? '';
      _videoUrlCtrl.text = e['video_url']?.toString() ?? '';
      _customerNameCtrl.text = e['customer_name']?.toString() ?? '';
      _customerRoleCtrl.text = e['customer_role']?.toString() ?? '';
      _machineId = e['machine_id']?.toString();
      final machineMap = e['machine'] as Map<String, dynamic>?;
      _machineName = machineMap?['machine_name']?.toString() ??
          e['machine_model']?.toString();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _categoryCtrl.dispose();
    _authorCtrl.dispose();
    _tagsCtrl.dispose();
    _thumbnailCtrl.dispose();
    _displayOrderCtrl.dispose();
    _pdfUrlCtrl.dispose();
    _videoUrlCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerRoleCtrl.dispose();
    super.dispose();
  }

  // ─── Data ────────────────────────────────────────────────────
  Future<void> _loadMachines() async {
    try {
      final res = await SupabaseConfig.client
          .from('machine_catalog')
          .select('id, machine_name, model_number, category, image_url')
          .order('machine_name', ascending: true);
      if (!mounted) return;
      setState(() {
        _machines = List<Map<String, dynamic>>.from(res);
        _machinesLoading = false;
        // If we're editing and the machine_id matches a row, capture its name.
        if (_machineId != null) {
          final m = _machines.firstWhere(
            (x) => x['id'] == _machineId,
            orElse: () => <String, dynamic>{},
          );
          if (m.isNotEmpty) _machineName = m['machine_name']?.toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _machinesLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final selectedMachine = _machineId == null
          ? null
          : _machines.firstWhere(
              (m) => m['id'] == _machineId,
              orElse: () => <String, dynamic>{},
            );

      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'content_type': _type,
        // For testimonials we store the quote inside `content`; for video we
        // store an optional summary; for manual the description; for article
        // the full body.
        'content': _contentCtrl.text.trim(),
        'category': _categoryCtrl.text.trim().isEmpty
            ? null
            : _categoryCtrl.text.trim(),
        'author':
            _authorCtrl.text.trim().isEmpty ? null : _authorCtrl.text.trim(),
        'tags': tags.isEmpty ? null : tags,
        'thumbnail_url': _thumbnailCtrl.text.trim().isEmpty
            ? null
            : _thumbnailCtrl.text.trim(),
        'display_order': int.tryParse(_displayOrderCtrl.text.trim()) ?? 0,
        'is_published': _isPublished,
        'pdf_url': _type == 'manual' && _pdfUrlCtrl.text.trim().isNotEmpty
            ? _pdfUrlCtrl.text.trim()
            : null,
        'video_url': _type == 'video' && _videoUrlCtrl.text.trim().isNotEmpty
            ? _videoUrlCtrl.text.trim()
            : null,
        'customer_name': _type == 'testimonial' &&
                _customerNameCtrl.text.trim().isNotEmpty
            ? _customerNameCtrl.text.trim()
            : null,
        'customer_role': _type == 'testimonial' &&
                _customerRoleCtrl.text.trim().isNotEmpty
            ? _customerRoleCtrl.text.trim()
            : null,
        'machine_id': _machineId,
        // Legacy denormalised fields kept in sync for the customer screens
        // that already read machine_model / machine_category.
        'machine_model': selectedMachine == null || selectedMachine.isEmpty
            ? null
            : (selectedMachine['model_number']?.toString() ??
                selectedMachine['machine_name']?.toString()),
        'machine_category': selectedMachine == null || selectedMachine.isEmpty
            ? null
            : selectedMachine['category']?.toString(),
      };

      if (_isEdit) {
        await SupabaseConfig.client
            .from('knowledge_base')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        // Stamp the author for new rows.
        final authId = SupabaseConfig.client.auth.currentUser?.id;
        if (authId != null) payload['author_id'] = authId;
        await SupabaseConfig.client
            .from('knowledge_base')
            .insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg, style: const TextStyle(color: Colors.white))),
        ]),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _types.firstWhere((t) => t.key == _type).color;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Edit Entry' : 'New Knowledge Entry',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        backgroundColor: Brand.surface(isDark),
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Save'),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
          children: [
            _sectionLabel('Type', isDark),
            _typeSelector(isDark),
            const SizedBox(height: 20),

            _sectionLabel('Basic Info', isDark),
            _card(isDark, [
              _field(
                _titleCtrl,
                isDark,
                label: 'Title',
                hint: _placeholderTitle(),
                icon: Icons.title_rounded,
                accent: accent,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              _divider(isDark),
              _machinePicker(isDark, accent),
              _divider(isDark),
              _field(
                _categoryCtrl,
                isDark,
                label: 'Category (optional)',
                hint: 'e.g. Maintenance, Setup, Safety',
                icon: Icons.category_rounded,
                accent: accent,
              ),
            ]),
            const SizedBox(height: 20),

            // Type-specific section
            ..._typeSpecificSection(isDark, accent),

            const SizedBox(height: 20),
            _sectionLabel('Presentation', isDark),
            _card(isDark, [
              _field(
                _thumbnailCtrl,
                isDark,
                label: 'Thumbnail URL (optional)',
                hint: 'https://...',
                icon: Icons.image_rounded,
                accent: accent,
                keyboardType: TextInputType.url,
              ),
              _divider(isDark),
              _field(
                _tagsCtrl,
                isDark,
                label: 'Tags (comma separated)',
                hint: 'safety, beginner, troubleshooting',
                icon: Icons.local_offer_rounded,
                accent: accent,
              ),
              _divider(isDark),
              _field(
                _displayOrderCtrl,
                isDark,
                label: 'Display order',
                hint: '0',
                icon: Icons.sort_rounded,
                accent: accent,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              _divider(isDark),
              SwitchListTile.adaptive(
                value: _isPublished,
                onChanged: (v) => setState(() => _isPublished = v),
                activeThumbColor: AdminColors.success,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  'Visible to customers',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AdminColors.text(context),
                  ),
                ),
                subtitle: Text(
                  _isPublished
                      ? 'Published — appears in customer Knowledge Base'
                      : 'Draft — hidden from customers',
                  style: TextStyle(
                      fontSize: 12, color: AdminColors.textSub(context)),
                ),
              ),
            ]),

            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_isEdit ? Icons.save_rounded : Icons.add_rounded),
                label: Text(
                  _saving
                      ? 'Saving...'
                      : (_isEdit ? 'Save changes' : 'Create entry'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Type chips ─────────────────────────────────────────────
  Widget _typeSelector(bool isDark) {
    return SizedBox(
      height: 92,
      child: Row(
        children: _types.map((t) {
          final sel = _type == t.key;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => _type = t.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: sel
                        ? t.color.withAlpha(isDark ? 60 : 30)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel
                          ? t.color
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: sel ? 1.6 : 1,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon,
                            size: 24,
                            color: sel
                                ? t.color
                                : AdminColors.textHint(context)),
                        const SizedBox(height: 6),
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w600,
                            color: sel ? t.color : AdminColors.textSub(context),
                          ),
                        ),
                      ],
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

  // ─── Type-specific fields ───────────────────────────────────
  List<Widget> _typeSpecificSection(bool isDark, Color accent) {
    switch (_type) {
      case 'manual':
        return [
          _sectionLabel('Manual', isDark),
          _card(isDark, [
            _field(
              _pdfUrlCtrl,
              isDark,
              label: 'PDF URL',
              hint: 'https://example.com/manual.pdf',
              icon: Icons.picture_as_pdf_rounded,
              accent: accent,
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'A PDF link is required for manuals';
                }
                if (!_looksLikeUrl(v)) return 'Enter a valid URL';
                return null;
              },
            ),
            _divider(isDark),
            _field(
              _contentCtrl,
              isDark,
              label: 'Description',
              hint: 'Short summary of what this manual covers',
              icon: Icons.notes_rounded,
              accent: accent,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
          ]),
        ];
      case 'article':
        return [
          _sectionLabel('Article', isDark),
          _card(isDark, [
            _field(
              _authorCtrl,
              isDark,
              label: 'Author (optional)',
              hint: 'e.g. Engineering Team',
              icon: Icons.person_rounded,
              accent: accent,
              textCapitalization: TextCapitalization.words,
            ),
            _divider(isDark),
            _field(
              _contentCtrl,
              isDark,
              label: 'Article body',
              hint: 'Full article text. Markdown supported on the customer side.',
              icon: Icons.article_rounded,
              accent: accent,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Body is required' : null,
            ),
          ]),
        ];
      case 'testimonial':
        return [
          _sectionLabel('Customer Testimonial', isDark),
          _card(isDark, [
            _field(
              _customerNameCtrl,
              isDark,
              label: 'Customer name',
              hint: 'e.g. Nimal Perera',
              icon: Icons.person_rounded,
              accent: accent,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Customer name is required'
                  : null,
            ),
            _divider(isDark),
            _field(
              _customerRoleCtrl,
              isDark,
              label: 'Role / Company (optional)',
              hint: 'e.g. CEO, ABC Industries',
              icon: Icons.work_rounded,
              accent: accent,
              textCapitalization: TextCapitalization.words,
            ),
            _divider(isDark),
            _field(
              _contentCtrl,
              isDark,
              label: 'Testimonial',
              hint: 'The customer\'s words about the machine or service',
              icon: Icons.format_quote_rounded,
              accent: accent,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Testimonial text is required'
                  : null,
            ),
          ]),
        ];
      case 'video':
        return [
          _sectionLabel('Video', isDark),
          _card(isDark, [
            _field(
              _videoUrlCtrl,
              isDark,
              label: 'Video URL',
              hint: 'YouTube, Vimeo or direct .mp4 link',
              icon: Icons.link_rounded,
              accent: accent,
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Video URL is required';
                }
                if (!_looksLikeUrl(v)) return 'Enter a valid URL';
                return null;
              },
            ),
            _divider(isDark),
            _field(
              _contentCtrl,
              isDark,
              label: 'Description (optional)',
              hint: 'What this video covers',
              icon: Icons.notes_rounded,
              accent: accent,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
          ]),
        ];
    }
    return const [];
  }

  String _placeholderTitle() {
    switch (_type) {
      case 'manual':
        return 'e.g. CO₂ Laser — Operator Manual v3';
      case 'article':
        return 'e.g. Setting up your fiber laser for cutting';
      case 'testimonial':
        return 'e.g. "Cut my downtime in half"';
      case 'video':
        return 'e.g. Daily maintenance walkthrough';
    }
    return 'Title';
  }

  // ─── Machine picker (sheet-based) ───────────────────────────
  Widget _machinePicker(bool isDark, Color accent) {
    return InkWell(
      onTap: _machinesLoading ? null : _openMachineSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.precision_manufacturing_rounded,
                size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linked machine (optional)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSub(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _machineName ?? 'Tap to select a machine',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _machineName == null
                          ? AdminColors.textHint(context)
                          : AdminColors.text(context),
                    ),
                  ),
                ],
              ),
            ),
            if (_machineId != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  _machineId = null;
                  _machineName = null;
                }),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  color: AdminColors.textHint(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _openMachineSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.surface(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final filtered = _machines.where((m) {
              if (q.isEmpty) return true;
              final hay = '${m['machine_name']} ${m['model_number']} ${m['category']}'
                  .toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.4,
              builder: (_, scroll) => Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdminColors.textHint(context).withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setSheet(() => q = v),
                      decoration: InputDecoration(
                        hintText: 'Search machines',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final m = filtered[i];
                        return ListTile(
                          leading: const Icon(
                              Icons.precision_manufacturing_rounded),
                          title: Text(m['machine_name']?.toString() ?? ''),
                          subtitle: Text(
                              '${m['model_number'] ?? ''} · ${m['category'] ?? ''}'),
                          onTap: () => Navigator.pop(sheetCtx, m),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _machineId = result['id']?.toString();
        _machineName = result['machine_name']?.toString();
      });
    }
  }

  // ─── Small UI helpers ───────────────────────────────────────
  bool _looksLikeUrl(String v) {
    final s = v.trim();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(
          height: 1,
          color: isDark ? Brand.darkBorder : Brand.borderLight),
    );
  }

  Widget _field(
    TextEditingController c,
    bool isDark, {
    required String label,
    required String hint,
    required IconData icon,
    required Color accent,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        validator: validator,
        style: TextStyle(
          color: AdminColors.text(context),
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(icon, size: 20, color: accent),
          ),
          border: InputBorder.none,
          labelStyle: TextStyle(
            color: AdminColors.textSub(context),
            fontSize: 13,
          ),
          hintStyle: TextStyle(
            color: AdminColors.textHint(context),
            fontSize: 14,
          ),
          errorStyle: const TextStyle(fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
