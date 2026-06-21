// lib/screens/marketing/ma_points_page.dart
// P9 — Points Activity: read-only feed of all point_activities with user info

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _ptColor = AdminColors.internal;

class MaPointsPage extends StatefulWidget {
  const MaPointsPage({super.key});

  @override
  State<MaPointsPage> createState() => _MaPointsPageState();
}

class _MaPointsPageState extends State<MaPointsPage> {
  List<Map<String, dynamic>> _activities = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _typeFilter = 'all';

  // Known activity types — for filter chips
  static const _knownTypes = [
    'all',
    'account_creation',
    'complete_profile',
    'create_ticket',
    'article_read',
    'machine_purchase',
    'installment_paid',
    'ticket_resolved',
    'daily_login',
    'referral_signup',
    'referral_qualified',
    'service_rating',
    'first_order',
  ];

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
          .from('point_activities')
          .select(
            'id, activity_type, points_earned, multiplier, final_points, '
            'description, created_at, '
            'user:users!user_id(id, full_name, username, profile_photo)',
          )
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _activities = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _activities;
    if (_typeFilter != 'all') {
      list = list.where((a) {
        return (a['activity_type'] as String? ?? '') == _typeFilter;
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((a) {
        final user = a['user'] as Map<String, dynamic>?;
        final name = (user?['full_name'] ?? '').toString().toLowerCase();
        final uname = (user?['username'] ?? '').toString().toLowerCase();
        final desc = (a['description'] ?? '').toString().toLowerCase();
        return name.contains(q) || uname.contains(q) || desc.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    // Only show type chips that actually appear in the data
    final activeTypes = {
      'all',
      ..._activities.map((a) => a['activity_type'] as String? ?? '').where((t) => t.isNotEmpty),
    };
    final chips = _knownTypes.where((t) => activeTypes.contains(t)).toList();

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Points Activity',
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
                    hintText: 'Search by user or description…',
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
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: chips
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
          // ── Count ──
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text('${filtered.length} activit${filtered.length == 1 ? 'y' : 'ies'}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textHint(context))),
            ),
          // ── List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _ptColor))
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
                              style: FilledButton.styleFrom(backgroundColor: _ptColor),
                            ),
                          ]),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _ptColor,
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
                                            color: _ptColor.withAlpha(20),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.stars_outlined,
                                              size: 36, color: _ptColor),
                                        ),
                                        const SizedBox(height: 20),
                                        Text('No activity found',
                                            style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                                        const SizedBox(height: 8),
                                        Text(_search.isNotEmpty ? 'Try a different search term.' : 'Points activity will appear here.',
                                            style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                                      ]),
                                ),
                              ])
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 40),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
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
    final isSelected = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _ptColor
              : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
              color: isSelected
                  ? _ptColor
                  : (isDark ? Brand.darkBorder : Brand.borderLight)),
        ),
        child: Text(
          value == 'all' ? 'All' : _typeLabel(value),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AdminColors.textHint(context)),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> a, bool isDark) {
    final user = a['user'] as Map<String, dynamic>?;
    final userName = user?['full_name'] as String? ?? 'Unknown';
    final username = user?['username'] as String? ?? '';
    final actType = a['activity_type'] as String? ?? '';
    final desc = a['description'] as String? ?? '';
    final finalPts = a['final_points'] as int? ?? 0;
    final multiplier = a['multiplier'];
    final createdAt = a['created_at'] as String?;

    final hasBonus = multiplier != null &&
        double.tryParse(multiplier.toString()) != null &&
        double.parse(multiplier.toString()) > 1.0;

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon orb ──
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _ptColor.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(Brand.r(12)),
            ),
            child: Icon(_iconFor(actType), size: 20, color: _ptColor),
          ),
          const SizedBox(width: 12),
          // ── Content ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User name + username
                Row(children: [
                  Expanded(
                    child: Text(userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark)),
                  ),
                  // Points badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _ptColor.withAlpha(isDark ? 30 : 20),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Text('+$finalPts pts',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _ptColor)),
                  ),
                ]),
                if (username.isNotEmpty)
                  Text('@$username',
                      style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context))),
                const SizedBox(height: 4),
                // Activity type chip
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      borderRadius: BorderRadius.circular(Brand.r(6)),
                      border: Border.all(
                          color: isDark
                              ? Brand.darkBorder
                              : Brand.borderLight),
                    ),
                    child: Text(_typeLabel(actType),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.textSub(context))),
                  ),
                  if (hasBonus) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AdminColors.warning.withAlpha(25),
                        borderRadius: BorderRadius.circular(Brand.r(6)),
                      ),
                      child: Text(
                        '${multiplier}x tier bonus',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.warning),
                      ),
                    ),
                  ],
                ]),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context))),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    TimeUtils.formatDateTime(
                        DateTime.tryParse(createdAt) ?? DateTime.now()),
                    style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.textHint(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'account_creation': return Icons.person_add_rounded;
      case 'complete_profile': return Icons.verified_user_rounded;
      case 'create_ticket': return Icons.confirmation_number_rounded;
      case 'article_read': return Icons.menu_book_rounded;
      case 'machine_purchase': return Icons.precision_manufacturing_rounded;
      case 'installment_paid': return Icons.payments_rounded;
      case 'ticket_resolved': return Icons.task_alt_rounded;
      case 'daily_login': return Icons.login_rounded;
      case 'login_streak_7': return Icons.local_fire_department_rounded;
      case 'login_streak_30': return Icons.whatshot_rounded;
      case 'referral_signup': return Icons.group_add_rounded;
      case 'referral_qualified': return Icons.handshake_rounded;
      case 'service_rating': return Icons.star_rounded;
      case 'first_order': return Icons.shopping_bag_rounded;
      default: return Icons.stars_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'all': return 'All';
      case 'account_creation': return 'Sign Up';
      case 'complete_profile': return 'Profile';
      case 'create_ticket': return 'Ticket';
      case 'article_read': return 'Article';
      case 'machine_purchase': return 'Purchase';
      case 'installment_paid': return 'Installment';
      case 'ticket_resolved': return 'Resolved';
      case 'daily_login': return 'Login';
      case 'login_streak_7': return '7-day Streak';
      case 'login_streak_30': return '30-day Streak';
      case 'referral_signup': return 'Referral';
      case 'referral_qualified': return 'Ref Qualified';
      case 'service_rating': return 'Rating';
      case 'first_order': return 'First Order';
      default: return type.replaceAll('_', ' ');
    }
  }
}
