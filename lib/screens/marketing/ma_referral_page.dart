// lib/screens/marketing/ma_referral_page.dart
// P2 — Referral Program: view referrals + manage commission rules

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';

const Color _refColor = Color(0xFF10B981);

class MaReferralPage extends StatefulWidget {
  const MaReferralPage({super.key});

  @override
  State<MaReferralPage> createState() => _MaReferralPageState();
}

class _MaReferralPageState extends State<MaReferralPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Referrals tab state ──
  List<Map<String, dynamic>> _referrals = [];
  bool _loadingReferrals = true;
  String _statusFilter = 'all';

  // ── Rules tab state ──
  List<Map<String, dynamic>> _rules = [];
  bool _loadingRules = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadReferrals();
    _loadRules();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReferrals() async {
    setState(() => _loadingReferrals = true);
    try {
      final res = await SupabaseConfig.client
          .from('referrals')
          .select('*, referrer:users!referrer_id(full_name, username), referred:users!referred_id(full_name, username)')
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _referrals = List<Map<String, dynamic>>.from(res);
        _loadingReferrals = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingReferrals = false);
    }
  }

  Future<void> _loadRules() async {
    setState(() => _loadingRules = true);
    try {
      final res = await SupabaseConfig.client
          .from('referral_commission_rules')
          .select()
          .order('min_purchase', ascending: true);
      if (!mounted) return;
      setState(() {
        _rules = List<Map<String, dynamic>>.from(res);
        _loadingRules = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRules = false);
    }
  }

  List<Map<String, dynamic>> get _filteredReferrals {
    if (_statusFilter == 'all') return _referrals;
    return _referrals.where((r) => r['status'] == _statusFilter).toList();
  }

  Future<void> _editRule(Map<String, dynamic> rule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RuleEditDialog(rule: rule),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseConfig.client.from('referral_commission_rules').update({
        'commission_type': result['commission_type'],
        'commission_value': result['commission_value'],
        'is_active': result['is_active'],
      }).eq('id', rule['id']);
      if (!mounted) return;
      _showSuccess('Commission rule updated');
      _loadRules();
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
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        title: Text('Referral Program',
            style: TextStyle(fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        elevation: 0, scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _refColor,
          labelColor: _refColor,
          unselectedLabelColor: AdminColors.textHint(context),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Referrals'),
            Tab(text: 'Commission Rules'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildReferralsTab(isDark),
          _buildRulesTab(isDark),
        ],
      ),
    );
  }

  Widget _buildReferralsTab(bool isDark) {
    final filtered = _filteredReferrals;
    return Column(
      children: [
        // Status filter
        Container(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'pending', 'qualified', 'approved', 'paid', 'expired']
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _statusFilter = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _statusFilter == s
                                  ? _refColor
                                  : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _statusFilter == s
                                      ? _refColor
                                      : (isDark ? Brand.darkBorder : Brand.borderLight)),
                            ),
                            child: Text(_cap(s),
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: _statusFilter == s
                                        ? Colors.white
                                        : AdminColors.textHint(context))),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: _loadingReferrals
              ? const Center(child: CircularProgressIndicator(color: _refColor))
              : RefreshIndicator(
                  onRefresh: _loadReferrals, color: _refColor,
                  child: filtered.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                color: _refColor.withAlpha(20),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.share_outlined, size: 36, color: _refColor),
                            ),
                            const SizedBox(height: 20),
                            Text('No referrals found',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                            const SizedBox(height: 8),
                            Text(_statusFilter != 'all'
                                ? 'No referrals with "${_cap(_statusFilter)}" status.'
                                : 'Referrals will appear here once customers start referring.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                          ])),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _buildReferralCard(filtered[i], isDark),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> r, bool isDark) {
    final status = r['status'] as String? ?? 'pending';
    final referrer = r['referrer'] as Map<String, dynamic>?;
    final referred = r['referred'] as Map<String, dynamic>?;
    final createdAt = r['created_at'] as String?;
    final commissionAmt = r['commission_amount'];

    final statusColor = _statusColor(status);

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
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(referrer?['full_name'] ?? 'Unknown',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
              Text('@${referrer?['username'] ?? '—'}',
                  style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
            ]),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(referred?['full_name'] ?? 'Unknown',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
              Text('@${referred?['username'] ?? '—'}',
                  style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_cap(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
          ),
          const Spacer(),
          if (commissionAmt != null)
            Text('Rs. ${_formatNum(commissionAmt)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _refColor)),
          if (createdAt != null) ...[
            const SizedBox(width: 10),
            Text(TimeUtils.formatDateShort(DateTime.tryParse(createdAt) ?? DateTime.now()),
                style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
          ],
        ]),
      ]),
    );
  }

  Widget _buildRulesTab(bool isDark) {
    return _loadingRules
        ? const Center(child: CircularProgressIndicator(color: _refColor))
        : RefreshIndicator(
            onRefresh: _loadRules, color: _refColor,
            child: _rules.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: _refColor.withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.rule_rounded, size: 36, color: _refColor),
                      ),
                      const SizedBox(height: 20),
                      Text('No commission rules',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                      const SizedBox(height: 8),
                      Text('Commission rules will appear here once configured.',
                          style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                    ])),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: _rules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildRuleCard(_rules[i], isDark),
                  ),
          );
  }

  Widget _buildRuleCard(Map<String, dynamic> rule, bool isDark) {
    final isActive = rule['is_active'] as bool? ?? true;
    final commType = rule['commission_type'] as String? ?? 'percentage';
    final commValue = rule['commission_value'];
    final minPurchase = rule['min_purchase'];
    final maxCommission = rule['max_commission'];
    final category = rule['category'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isActive
                ? _refColor.withAlpha(isDark ? 60 : 40)
                : (isDark ? Brand.darkBorder : Brand.borderLight)),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              category != null ? _cap(category) : 'All Categories',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isActive ? _refColor : AdminColors.textHint(context)).withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(isActive ? 'Active' : 'Inactive',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: isActive ? _refColor : AdminColors.textHint(context))),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          if (commValue != null)
            _infoChip(
              commType == 'percentage' ? 'Rate' : 'Fixed',
              commType == 'percentage' ? '$commValue%' : 'Rs. ${_formatNum(commValue)}',
              isDark,
            ),
          if (minPurchase != null)
            _infoChip('Min Purchase', 'Rs. ${_formatNum(minPurchase)}', isDark),
          if (maxCommission != null)
            _infoChip('Max Commission', 'Rs. ${_formatNum(maxCommission)}', isDark),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _editRule(rule),
            icon: const Icon(Icons.edit_rounded, size: 14),
            label: const Text('Edit Rule'),
            style: TextButton.styleFrom(foregroundColor: _refColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ),
        ),
      ]),
    );
  }

  Widget _infoChip(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        borderRadius: BorderRadius.circular(8),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: AdminColors.textHint(context))),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return AdminColors.success;
      case 'paid': return const Color(0xFF10B981);
      case 'qualified': return AdminColors.info;
      case 'expired': return AdminColors.error;
      case 'rejected': return AdminColors.error;
      default: return AdminColors.warning;
    }
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatNum(dynamic v) {
    if (v == null) return '0';
    final n = double.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }
}

// ─── Rule Edit Dialog ──────────────────────────────────────────────────────────

class _RuleEditDialog extends StatefulWidget {
  final Map<String, dynamic> rule;
  const _RuleEditDialog({required this.rule});

  @override
  State<_RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<_RuleEditDialog> {
  final _valueCtrl = TextEditingController();
  late String _commType;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _commType = widget.rule['commission_type'] as String? ?? 'percentage';
    _valueCtrl.text = (widget.rule['commission_value'] ?? '').toString();
    _isActive = widget.rule['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Commission Rule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Commission type selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'percentage', label: Text('Percentage')),
              ButtonSegment(value: 'fixed', label: Text('Fixed')),
            ],
            selected: {_commType},
            onSelectionChanged: (v) => setState(() => _commType = v.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: const Color(0xFF10B981).withAlpha(30),
              selectedForegroundColor: const Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: _commType == 'percentage' ? 'Commission Rate (%)' : 'Fixed Amount (Rs.)',
                border: const OutlineInputBorder(),
                hintText: _commType == 'percentage' ? 'e.g. 5' : 'e.g. 500'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Active'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            activeThumbColor: const Color(0xFF10B981),
            contentPadding: EdgeInsets.zero,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'commission_type': _commType,
            'commission_value': double.tryParse(_valueCtrl.text),
            'is_active': _isActive,
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
