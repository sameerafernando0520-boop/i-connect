// lib/screens/marketing/ma_banners_page.dart
// P4 — Promotional Banners: full CRUD

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

const Color _bannerColor = Color(0xFFEC4899);

class MaBannersPage extends StatefulWidget {
  const MaBannersPage({super.key});

  @override
  State<MaBannersPage> createState() => _MaBannersPageState();
}

class _MaBannersPageState extends State<MaBannersPage> {
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client
          .from('promotional_banners')
          .select()
          .order('display_order', ascending: true);
      if (!mounted) return;
      setState(() { _banners = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _BannerFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      String? imageUrl;
      if (result['imageFile'] != null) {
        imageUrl = await _uploadImage(result['imageFile'] as File);
      }
      await SupabaseConfig.client.from('promotional_banners').insert({
        'title': result['title'],
        'subtitle': result['subtitle'],
        'image_url': imageUrl ?? '',
        'link_type': 'url',
        'link_value': result['action_url'],
        'is_active': result['is_active'],
        'display_order': _banners.length,
      });
      if (!mounted) return;
      _showSuccess('Banner added successfully');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _edit(Map<String, dynamic> banner) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BannerFormDialog(initial: banner),
    );
    if (result == null || !mounted) return;
    try {
      String? imageUrl = banner['image_url'];
      if (result['imageFile'] != null) {
        imageUrl = await _uploadImage(result['imageFile'] as File);
      }
      await SupabaseConfig.client.from('promotional_banners').update({
        'title': result['title'],
        'subtitle': result['subtitle'],
        'image_url': imageUrl ?? '',
        'link_value': result['action_url'],
        'is_active': result['is_active'],
      }).eq('id', banner['id']);
      if (!mounted) return;
      _showSuccess('Banner updated');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> banner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Banner'),
        content: Text('Delete "${banner['title']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AdminColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseConfig.client.from('promotional_banners').delete().eq('id', banner['id']);
      if (!mounted) return;
      _showSuccess('Banner deleted');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> banner) async {
    final newVal = !(banner['is_active'] as bool? ?? false);
    try {
      await SupabaseConfig.client.from('promotional_banners')
          .update({'is_active': newVal}).eq('id', banner['id']);
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<String> _uploadImage(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final path = 'banners/${const Uuid().v4()}.$ext';
    await SupabaseConfig.client.storage
        .from('promotional-banners')
        .upload(path, file, fileOptions: FileOptions(contentType: 'image/$ext'));
    return SupabaseConfig.client.storage.from('promotional-banners').getPublicUrl(path);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: AdminColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: Text('Promotional Banners',
            style: TextStyle(fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        backgroundColor: Brand.surface(isDark),
        elevation: 0, scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _bannerColor))
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
                      style: FilledButton.styleFrom(backgroundColor: _bannerColor),
                    ),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load, color: _bannerColor,
                  child: _banners.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                color: _bannerColor.withAlpha(20),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.image_not_supported_rounded, size: 36, color: _bannerColor),
                            ),
                            const SizedBox(height: 20),
                            Text('No banners yet',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                            const SizedBox(height: 8),
                            Text('Tap + to add your first promotional banner.',
                                style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                          ])),
                        ])
                      : Column(
                          children: [
                            // Count header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                              child: Row(children: [
                                Text('${_banners.length} banner${_banners.length == 1 ? '' : 's'}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                        color: AdminColors.textHint(context))),
                                const Spacer(),
                                Text('Ordered by display position',
                                    style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
                              ]),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                                itemCount: _banners.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _buildCard(_banners[i], isDark),
                              ),
                            ),
                          ],
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: const Text('Add Banner', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _bannerColor, foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> b, bool isDark) {
    final isActive = b['is_active'] as bool? ?? false;
    final imgUrl = b['image_url'] as String?;
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imgUrl != null && imgUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: CachedNetworkImage(
                imageUrl: imgUrl, height: 140, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 140, color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: (_, __, ___) => Container(height: 140, color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    child: const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 40)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b['title'] ?? 'Untitled', style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                    if ((b['subtitle'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(b['subtitle'].toString(), maxLines: 2,
                          style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
                    ],
                  ],
                )),
                // Active toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isActive ? AdminColors.success : AdminColors.textHint(context)).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isActive ? 'Active' : 'Hidden',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: isActive ? AdminColors.success : AdminColors.textHint(context))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                _btn(Icons.edit_rounded, 'Edit', _bannerColor, isDark, () => _edit(b)),
                const SizedBox(width: 8),
                _btn(isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    isActive ? 'Hide' : 'Show',
                    isActive ? AdminColors.warning : AdminColors.success, isDark, () => _toggleActive(b)),
                const SizedBox(width: 8),
                _btn(Icons.delete_outline_rounded, 'Delete', AdminColors.error, isDark, () => _delete(b)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, Color color, bool isDark, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 25 : 12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
          ),
          child: Column(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }
}

class _BannerFormDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _BannerFormDialog({this.initial});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _isActive = true;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    if (b != null) {
      _titleCtrl.text = b['title'] ?? '';
      _subtitleCtrl.text = b['subtitle'] ?? '';
      _urlCtrl.text = b['link_value'] ?? b['action_url'] ?? '';
      _isActive = b['is_active'] as bool? ?? true;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _subtitleCtrl.dispose(); _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Banner' : 'Edit Banner'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Image picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 100, width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withAlpha(80)),
              ),
              child: _imageFile != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Image.file(_imageFile!, fit: BoxFit.cover))
                  : (widget.initial?['image_url'] != null && (widget.initial?['image_url'] as String).isNotEmpty)
                      ? ClipRRect(borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(imageUrl: widget.initial!['image_url'], fit: BoxFit.cover))
                      : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_rounded, size: 32, color: Colors.grey),
                          SizedBox(height: 4),
                          Text('Tap to select image', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _subtitleCtrl,
              decoration: const InputDecoration(labelText: 'Subtitle (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'Action URL (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Active'), value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            activeTrackColor: _bannerColor.withAlpha(128), thumbColor: WidgetStatePropertyAll(_bannerColor), contentPadding: EdgeInsets.zero,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'title': _titleCtrl.text.trim(),
              'subtitle': _subtitleCtrl.text.trim(),
              'action_url': _urlCtrl.text.trim(),
              'is_active': _isActive,
              'imageFile': _imageFile,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: _bannerColor, foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
