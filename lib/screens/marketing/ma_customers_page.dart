// lib/screens/marketing/ma_customers_page.dart
// P1 — Customers: read-only list with tier badges and basic profile info

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';

const Color _custColor = Color(0xFF3B82F6);

class MaCustomersPage extends StatefulWidget {
  const MaCustomersPage({super.key});

  @override
  State<MaCustomersPage> createState() => _MaCustomersPageState();
}

class _MaCustomersPageState extends State<MaCustomersPage> {
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _tierFilter = 'all';

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
          .from('users')
          .select('id, full_name, username, profile_photo, created_at, customer_tiers(current_tier, total_points)')
          .eq('role', 'customer')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _customers = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _customers;
    if (_tierFilter != 'all') {
      list = list.where((c) {
        final tierData = c['customer_tiers'];
        final tier = tierData is List && tierData.isNotEmpty
            ? tierData.first['current_tier'] as String? ?? 'bronze'
            : tierData is Map ? tierData['current_tier'] as String? ?? 'bronze' : 'bronze';
        return tier.toLowerCase() == _tierFilter.toLowerCase();
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final uname = (c['username'] ?? '').toString().toLowerCase();
        return name.contains(q) || uname.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        title: Text('Customers',
            style: TextStyle(fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        elevation: 0, scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // ── Search + Filter ──
          Container(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or @username…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                        : null,
                    filled: true,
                    fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['all', 'bronze', 'silver', 'gold', 'platinum']
                        .map((t) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _filterChip(t, isDark),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          // ── Customer Count ──
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text('${filtered.length} customers',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AdminColors.textHint(context))),
            ),
          // ── List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _custColor))
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
                            style: FilledButton.styleFrom(backgroundColor: _custColor),
                          ),
                        ]),
                      ))
                    : RefreshIndicator(
                        onRefresh: _load, color: _custColor,
                        child: filtered.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 80),
                                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    width: 72, height: 72,
                                    decoration: BoxDecoration(
                                      color: _custColor.withAlpha(20),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.people_outline_rounded, size: 36, color: _custColor),
                                  ),
                                  const SizedBox(height: 20),
                                  Text('No customers found',
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                                  const SizedBox(height: 8),
                                  Text(_search.isNotEmpty ? 'Try a different search term.' : 'Customers will appear here once they sign up.',
                                      style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                                ])),
                              ])
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _buildCard(filtered[i], isDark),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, bool isDark) {
    final isSelected = _tierFilter == value;
    final color = value == 'all' ? _custColor : _tierColorFor(value);
    return GestureDetector(
      onTap: () => setState(() => _tierFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : (isDark ? Brand.darkBorder : Brand.borderLight)),
        ),
        child: Text(_cap(value),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AdminColors.textHint(context))),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> c, bool isDark) {
    final name = c['full_name'] as String? ?? 'Unknown';
    final username = c['username'] as String? ?? '';
    final photoUrl = c['profile_photo'] as String?;
    final createdAt = c['created_at'] as String?;

    final tierData = c['customer_tiers'];
    String tier = 'bronze';
    int points = 0;
    if (tierData is List && tierData.isNotEmpty) {
      tier = tierData.first['current_tier'] as String? ?? 'bronze';
      points = tierData.first['total_points'] as int? ?? 0;
    } else if (tierData is Map) {
      tier = tierData['current_tier'] as String? ?? 'bronze';
      points = tierData['total_points'] as int? ?? 0;
    }

    final tierColor = _tierColorFor(tier);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 24,
          backgroundColor: _custColor.withAlpha(isDark ? 30 : 15),
          child: photoUrl != null && photoUrl.isNotEmpty
              ? ClipOval(child: CachedNetworkImage(
                  imageUrl: photoUrl, width: 48, height: 48, fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(),
                  errorWidget: (_, __, ___) => Text(name[0].toUpperCase(),
                      style: const TextStyle(color: _custColor, fontWeight: FontWeight.w700, fontSize: 18)),
                ))
              : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: _custColor, fontWeight: FontWeight.w700, fontSize: 18)),
        ),
        const SizedBox(width: 12),
        // Info
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            Text('@$username',
                style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tierColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_cap(tier),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tierColor)),
              ),
              const SizedBox(width: 6),
              Text('$points pts',
                  style: TextStyle(fontSize: 10, color: AdminColors.textHint(context))),
            ]),
          ]),
        ),
        // Right side
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AdminColors.success.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Active',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: AdminColors.success)),
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Text(TimeUtils.formatDateShort(DateTime.tryParse(createdAt) ?? DateTime.now()),
                style: TextStyle(fontSize: 10, color: AdminColors.textHint(context))),
          ],
        ]),
      ]),
    );
  }

  Color _tierColorFor(String tier) {
    switch (tier.toLowerCase()) {
      case 'silver': return const Color(0xFFC0C0C0);
      case 'gold': return const Color(0xFFFFD700);
      case 'platinum': return const Color(0xFF00B4D8);
      default: return const Color(0xFFCD7F32);
    }
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
