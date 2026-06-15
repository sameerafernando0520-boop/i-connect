// lib/screens/marketing/ma_catalog_page.dart
// P8 — Machine Catalog: read-only browser with search + category filter

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _catColor = Color(0xFF14B8A6);

class MaCatalogPage extends StatefulWidget {
  const MaCatalogPage({super.key});

  @override
  State<MaCatalogPage> createState() => _MaCatalogPageState();
}

class _MaCatalogPageState extends State<MaCatalogPage> {
  List<Map<String, dynamic>> _machines = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _categoryFilter = 'all';

  // Known machine categories — populated dynamically from data
  final Set<String> _categories = {};

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
          .from('machine_catalog')
          .select('id, machine_name, model_number, brand, category, price, is_active, image_url, description')
          .order('created_at', ascending: false);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(res);
      final cats = <String>{};
      for (final m in list) {
        final cat = m['category'] as String?;
        if (cat != null && cat.isNotEmpty) cats.add(cat);
      }
      setState(() {
        _machines = list;
        _categories
          ..clear()
          ..addAll(cats);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _machines;
    if (_categoryFilter != 'all') {
      list = list.where((m) {
        final cat = (m['category'] as String? ?? '').toLowerCase();
        return cat == _categoryFilter.toLowerCase();
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) {
        final name = (m['machine_name'] ?? '').toString().toLowerCase();
        final brand = (m['brand'] ?? '').toString().toLowerCase();
        final model = (m['model_number'] ?? '').toString().toLowerCase();
        return name.contains(q) || brand.contains(q) || model.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;
    final allCats = ['all', ..._categories.toList()..sort()];

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Machine Catalog',
        accent: HeroAccent.violet,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // ── Search + Filter ──
          Container(
            color: Brand.surface(isDark),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name, brand, or model…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            })
                        : null,
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                if (_categories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: allCats
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _filterChip(c, isDark),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Count row ──
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text('${filtered.length} machine${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textHint(context))),
            ),
          // ── List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _catColor))
                : _error != null
                    ? Center(
                        child: Padding(
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
                              style: FilledButton.styleFrom(backgroundColor: _catColor),
                            ),
                          ]),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _catColor,
                        child: filtered.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 80),
                                Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 72, height: 72,
                                          decoration: BoxDecoration(
                                            color: _catColor.withAlpha(20),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.precision_manufacturing_outlined,
                                              size: 36, color: _catColor),
                                        ),
                                        const SizedBox(height: 20),
                                        Text('No machines found',
                                            style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                                        const SizedBox(height: 8),
                                        Text(_search.isNotEmpty ? 'Try a different search term.' : 'No machines in catalog yet.',
                                            style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                                      ]),
                                ),
                              ])
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) =>
                                    _buildCard(filtered[i], isDark),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, bool isDark) {
    final isSelected = _categoryFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _categoryFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _catColor
              : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected
                  ? _catColor
                  : (isDark ? Brand.darkBorder : Brand.borderLight)),
        ),
        child: Text(
          value == 'all' ? 'All' : _cap(value),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AdminColors.textHint(context)),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> m, bool isDark) {
    final name = m['machine_name'] as String? ?? 'Unknown';
    final brand = m['brand'] as String? ?? '';
    final model = m['model_number'] as String? ?? '';
    final category = m['category'] as String? ?? '';
    final price = m['price'];
    final isAvailable = m['is_active'] as bool? ?? true;
    final imageUrl = m['image_url'] as String?;
    final description = m['description'] as String? ?? '';

    final priceStr = price != null
        ? 'Rs. ${_formatPrice(price)}'
        : 'Price on request';

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context, m, isDark),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Thumbnail ──
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 72, height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _imagePlaceholder(isDark),
                        errorWidget: (_, __, ___) => _imagePlaceholder(isDark),
                      )
                    : _imagePlaceholder(isDark),
              ),
              const SizedBox(width: 12),
              // ── Info ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + availability
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.royalBlueDark)),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isAvailable
                                    ? AdminColors.success
                                    : AdminColors.error)
                                .withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isAvailable ? 'Available' : 'Unavailable',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isAvailable
                                    ? AdminColors.success
                                    : AdminColors.error),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Brand + model
                    Text(
                      [if (brand.isNotEmpty) brand, if (model.isNotEmpty) model]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textSub(context)),
                    ),
                    const SizedBox(height: 4),
                    // Category chip
                    if (category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _catColor.withAlpha(isDark ? 30 : 20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_cap(category),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _catColor)),
                      ),
                    const SizedBox(height: 6),
                    // Price
                    Text(priceStr,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark)),
                    // Description snippet
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: AdminColors.textHint(context))),
                    ],
                  ],
                ),
              ),
              // Chevron
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: AdminColors.textHint(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder(bool isDark) => Container(
        width: 72, height: 72,
        color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        child: const Icon(Icons.precision_manufacturing_rounded,
            size: 28, color: _catColor),
      );

  void _showDetail(BuildContext context, Map<String, dynamic> m, bool isDark) {
    final name = m['machine_name'] as String? ?? 'Unknown';
    final brand = m['brand'] as String? ?? '';
    final model = m['model_number'] as String? ?? '';
    final category = m['category'] as String? ?? '';
    final price = m['price'];
    final isAvailable = m['is_active'] as bool? ?? true;
    final imageUrl = m['image_url'] as String?;
    final description = m['description'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight
                          : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Image
                if (imageUrl != null && imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 220,
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.scaffoldLight,
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: _catColor)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 220,
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.scaffoldLight,
                        child: const Icon(
                            Icons.precision_manufacturing_rounded,
                            size: 56, color: _catColor),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.precision_manufacturing_rounded,
                        size: 56, color: _catColor),
                  ),
                const SizedBox(height: 20),
                // Title row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isAvailable
                                ? AdminColors.success
                                : AdminColors.error)
                            .withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isAvailable ? 'Available' : 'Unavailable',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isAvailable
                                ? AdminColors.success
                                : AdminColors.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Meta row
                _detailRow(Icons.business_rounded, brand, isDark),
                if (model.isNotEmpty)
                  _detailRow(Icons.tag_rounded, model, isDark),
                if (category.isNotEmpty)
                  _detailRow(Icons.category_rounded, _cap(category), isDark),
                const SizedBox(height: 12),
                // Price
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _catColor.withAlpha(isDark ? 25 : 15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money_rounded,
                          color: _catColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        price != null
                            ? 'Rs. ${_formatPrice(price)}'
                            : 'Price on request',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _catColor),
                      ),
                    ],
                  ),
                ),
                // Description
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Description',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                  const SizedBox(height: 8),
                  Text(description,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: AdminColors.textSub(context))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, bool isDark) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: AdminColors.textHint(context)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12, color: AdminColors.textSub(context))),
      ]),
    );
  }

  String _formatPrice(dynamic price) {
    try {
      final n = double.parse(price.toString());
      if (n == n.truncateToDouble()) {
        return n.toInt().toString().replaceAllMapped(
            RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
      }
      return n.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    } catch (_) {
      return price.toString();
    }
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
